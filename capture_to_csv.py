# capture_to_csv.py
import csv
import argparse
from datetime import datetime, timedelta
import os
from collections import defaultdict
import asyncio
import shutil

UPLOAD_DIR = os.path.join(os.path.dirname(__file__), 'uploads')

def safe_get_ip(packet):
    if hasattr(packet, 'ip'):
        return packet.ip.src, packet.ip.dst
    if hasattr(packet, 'ipv6'):
        return packet.ipv6.src, packet.ipv6.dst
    return '', ''

def safe_get_ports(packet):
    if hasattr(packet, 'tcp'):
        return getattr(packet.tcp, 'srcport', ''), getattr(packet.tcp, 'dstport', '')
    if hasattr(packet, 'udp'):
        return getattr(packet.udp, 'srcport', ''), getattr(packet.udp, 'dstport', '')
    return '', ''

def safe_length(packet):
    try:
        return packet.length
    except Exception:
        try:
            return packet.frame_info.len
        except Exception:
            return ''

def aggregate_rows(rows, window_seconds=30):
    """将抓到的原始报文按 (src_ip, src_port, dst_ip, dst_port, protocol, 时间窗口) 聚合，
    计算 bytes_transferred、packet_count、connection_duration 等特征。
    rows: [ts, src_ip, src_port, dst_ip, dst_port, proto, length, info]
    """
    agg = defaultdict(lambda: {
        'first_ts': None,
        'last_ts': None,
        'bytes_sum': 0,
        'packet_count': 0,
        'src_port': None,
        'dst_port': None,
        'protocol': None,
    })

    for ts, src_ip, src_port, dst_ip, dst_port, proto, length, info in rows:
        if not ts:
            continue
        try:
            ts_dt = datetime.fromisoformat(str(ts))
        except Exception:
            # 时间解析失败，跳过该报文
            continue

        # 以 window_seconds 为粒度做时间窗口，例如 30 秒
        try:
            ts_epoch = ts_dt.timestamp()
            window_start_epoch = (ts_epoch // window_seconds) * window_seconds
            window_start = datetime.fromtimestamp(window_start_epoch)
        except Exception:
            # timestamp 异常时退化为按分钟窗口
            window_start = ts_dt.replace(second=0, microsecond=0)

        key = (src_ip, src_port, dst_ip, dst_port, proto, window_start)
        d = agg[key]

        d['src_port'] = src_port
        d['dst_port'] = dst_port
        d['protocol'] = proto

        if d['first_ts'] is None or ts_dt < d['first_ts']:
            d['first_ts'] = ts_dt
        if d['last_ts'] is None or ts_dt > d['last_ts']:
            d['last_ts'] = ts_dt

        # 累加字节和包数
        try:
            l = int(length)
        except Exception:
            l = 0
        if l < 0:
            l = 0

        d['bytes_sum'] += l
        d['packet_count'] += 1

    aggregated = []
    for (src_ip, src_port, dst_ip, dst_port, proto, window_start), d in agg.items():
        first_ts = d['first_ts']
        last_ts = d['last_ts']
        if first_ts and last_ts:
            duration = (last_ts - first_ts).total_seconds()
        else:
            duration = 1.0
        if duration <= 0:
            duration = 1.0

        bytes_transferred = d['bytes_sum']
        packet_count = d['packet_count']
        bytes_per_packet = bytes_transferred / packet_count if packet_count > 0 else 0.0
        packets_per_second = packet_count / duration if duration > 0 else 0.0

        # 目前不从 TCP 底层字段计算重传率，先设为 0.0
        retransmission_rate = 0.0

        aggregated.append({
            'timestamp': window_start.isoformat(),
            'bytes_transferred': bytes_transferred,
            'packet_count': packet_count,
            'connection_duration': duration,
            'source_port': src_port,
            'destination_port': dst_port,
            'retransmission_rate': retransmission_rate,
            'protocol': proto,
            'bytes_per_packet': bytes_per_packet,
            'packets_per_second': packets_per_second,
        })

    return aggregated


# 新增：实时滚动聚合器，用于逐包聚合并在完成的时间窗口时刷写到磁盘
class RollingAggregator:
    def __init__(self, window_seconds=30):
        self.window_seconds = window_seconds
        self.agg = defaultdict(lambda: {
            'first_ts': None,
            'last_ts': None,
            'bytes_sum': 0,
            'packet_count': 0,
            'src_port': None,
            'dst_port': None,
            'protocol': None,
        })

    def _window_start(self, ts_dt: datetime):
        try:
            ts_epoch = ts_dt.timestamp()
            window_start_epoch = (ts_epoch // self.window_seconds) * self.window_seconds
            # If the incoming datetime is timezone-aware, preserve tzinfo when creating window start
            if getattr(ts_dt, 'tzinfo', None):
                return datetime.fromtimestamp(window_start_epoch, tz=ts_dt.tzinfo)
            return datetime.fromtimestamp(window_start_epoch)
        except Exception:
            return ts_dt.replace(second=0, microsecond=0)

    def add_packet(self, ts_dt: datetime, src_ip, src_port, dst_ip, dst_port, proto, length):
        key = (src_ip, src_port, dst_ip, dst_port, proto, self._window_start(ts_dt))
        d = self.agg[key]
        d['src_port'] = src_port
        d['dst_port'] = dst_port
        d['protocol'] = proto

        if d['first_ts'] is None or ts_dt < d['first_ts']:
            d['first_ts'] = ts_dt
        if d['last_ts'] is None or ts_dt > d['last_ts']:
            d['last_ts'] = ts_dt

        try:
            l = int(length)
        except Exception:
            l = 0
        if l < 0:
            l = 0

        d['bytes_sum'] += l
        d['packet_count'] += 1

    def flush_older_than(self, cutoff_dt: datetime):
        # 刷新所有 window_start < cutoff_dt
        to_flush = []
        for (src_ip, src_port, dst_ip, dst_port, proto, window_start), d in list(self.agg.items()):
            should_flush = False
            try:
                # normal comparison for naive/aware datetimes with matching tzinfo
                if window_start < cutoff_dt:
                    should_flush = True
            except TypeError:
                # fallback: compare by epoch timestamps to handle naive vs aware datetimes
                try:
                    if window_start.timestamp() < cutoff_dt.timestamp():
                        should_flush = True
                except Exception:
                    # if timestamp also fails, skip this window
                    should_flush = False

            if should_flush:
                 # 生成聚合结果
                 first_ts = d['first_ts']
                 last_ts = d['last_ts']
                 if first_ts and last_ts:
                     duration = (last_ts - first_ts).total_seconds()
                 else:
                     duration = 1.0
                 if duration <= 0:
                     duration = 1.0

                 bytes_transferred = d['bytes_sum']
                 packet_count = d['packet_count']
                 bytes_per_packet = bytes_transferred / packet_count if packet_count > 0 else 0.0
                 packets_per_second = packet_count / duration if duration > 0 else 0.0
                 retransmission_rate = 0.0

                 to_flush.append({
                     'timestamp': window_start.isoformat(),
                     'bytes_transferred': bytes_transferred,
                     'packet_count': packet_count,
                     'connection_duration': duration,
                     'source_port': src_port,
                     'destination_port': dst_port,
                     'retransmission_rate': retransmission_rate,
                     'protocol': proto,
                     'bytes_per_packet': bytes_per_packet,
                     'packets_per_second': packets_per_second,
                 })
                 # 从内存中移除
                 del self.agg[(src_ip, src_port, dst_ip, dst_port, proto, window_start)]
        return to_flush

    def flush_all(self):
        # 刷新剩下的所有窗口
        # use a very large cutoff that matches tzinfo if possible; try to pick a tz-aware max if any keys have tzinfo
        tzinfo = None
        for (_, _, _, _, _, window_start) in self.agg.keys():
            if getattr(window_start, 'tzinfo', None):
                tzinfo = window_start.tzinfo
                break
        if tzinfo:
            cutoff = datetime.max.replace(tzinfo=tzinfo)
        else:
            cutoff = datetime.max
        return self.flush_older_than(cutoff)


def capture_to_csv(interface, duration, bpf_filter, output_file, max_packets, tshark_path=None):
    # 确保当前线程有 asyncio 事件循环（pyshark 在某些环境下需要）
    try:
        asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    # 如果用户没有显式提供输出文件名，则在 uploads 目录下生成带时间戳的文件名
    auto_generated_name = False
    if not output_file:
        auto_generated_name = True
        os.makedirs(UPLOAD_DIR, exist_ok=True)
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = os.path.join(UPLOAD_DIR, f'network_traffic_{timestamp}.csv')

    # Try to ensure pyshark can find tshark. Priority:
    # 1) explicit --tshark-path argument, 2) existing TSHARK_PATH env, 3) shutil.which('tshark') / 'tshark.exe'
    if tshark_path:
        os.environ['TSHARK_PATH'] = str(tshark_path)
        tshark_exec = str(tshark_path)
    else:
        tshark_exec = os.environ.get('TSHARK_PATH') or shutil.which('tshark') or shutil.which('tshark.exe')
        if tshark_exec:
            os.environ['TSHARK_PATH'] = str(tshark_exec)

    # import pyshark after setting environment so it can detect TShark path
    try:
        import pyshark
        from pyshark.tshark.tshark import TSharkNotFoundException
    except Exception as e:
        print("Failed to import pyshark. Ensure pyshark is installed (pip install pyshark).")
        raise

    try:
        # Pass explicit tshark path if we found one; pyshark will also check TSHARK_PATH
        capture = pyshark.LiveCapture(interface=interface, bpf_filter=bpf_filter, tshark_path=(tshark_exec if 'tshark_exec' in locals() else None))
    except TSharkNotFoundException as e:
        print("TShark not found by pyshark. Ensure tshark is installed and on PATH, or provide --tshark-path.")
        print("Error details:", e)
        raise

    # 打开输出文件，立即写入表头以防程序中途终止
    output_dir = os.path.dirname(output_file)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    # 明确确保输出文件存在（以便后续检查文件大小/写表头）
    try:
        open(output_file, 'a', encoding='utf-8').close()
    except Exception:
        # 如果无法在指定位置创建文件，抛出更明确的异常
        raise
    header = [
        'timestamp',
        'bytes_transferred',
        'packet_count',
        'connection_duration',
        'source_port',
        'destination_port',
        'retransmission_rate',
        'protocol',
        'bytes_per_packet',
        'packets_per_second',
    ]
    # 使用追加模式，如果文件为空则写入表头
    write_header = not os.path.exists(output_file) or os.path.getsize(output_file) == 0
    out_f = open(output_file, 'a', newline='', encoding='utf-8')
    writer = csv.writer(out_f)
    if write_header:
        writer.writerow(header)
        out_f.flush()

    # 使用滚动聚合器，window_seconds 与 aggregate_rows 保持一致
    window_seconds = 30
    aggregator = RollingAggregator(window_seconds=window_seconds)

    # 捕获（timeout 单位为秒），或限制包数量
    iter_packets = None
    try:
        if duration:
            capture.sniff(timeout=duration)
            # pyshark 在 sniff 后会把包保存在 capture._packets 中
            iter_packets = list(getattr(capture, '_packets', []))
            try:
                capture.close()
            except Exception:
                pass
        elif max_packets:
            capture.sniff(packet_count=max_packets)
            iter_packets = list(getattr(capture, '_packets', []))
            try:
                capture.close()
            except Exception:
                pass
        else:
            # 持续捕获：逐包处理，直到手动中断（Ctrl+C）
            for pkt in capture.sniff_continuously(packet_count=0):
                try:
                    ts_dt = getattr(pkt, 'sniff_time', None)
                    if not ts_dt:
                        # 退化为字符串时间戳解析
                        ts_str = getattr(pkt, 'sniff_timestamp', '')
                        try:
                            ts_dt = datetime.fromisoformat(ts_str)
                        except Exception:
                            ts_dt = None

                    src_ip, dst_ip = safe_get_ip(pkt)
                    src_port, dst_port = safe_get_ports(pkt)
                    proto = getattr(pkt, 'highest_layer', '') or getattr(pkt, '_ws.col.Protocol', '')
                    length = safe_length(pkt)

                    if ts_dt:
                        aggregator.add_packet(ts_dt, src_ip, src_port, dst_ip, dst_port, proto, length)
                        # 刷新早于当前窗口（当前时间 - window_seconds）的窗口
                        cutoff = ts_dt - timedelta(seconds=window_seconds)
                        flushed = aggregator.flush_older_than(cutoff)
                        for item in flushed:
                            writer.writerow([
                                item['timestamp'],
                                item['bytes_transferred'],
                                item['packet_count'],
                                item['connection_duration'],
                                item['source_port'],
                                item['destination_port'],
                                item['retransmission_rate'],
                                item['protocol'],
                                item['bytes_per_packet'],
                                item['packets_per_second'],
                            ])
                        out_f.flush()
                    else:
                        # 如果时间不可用，忽略或缓存在内存中（此处忽略）
                        continue
                except Exception:
                    # 忽略单个解析错误
                    continue
            # 持续捕获退出后，尝试关闭
            try:
                capture.close()
            except Exception:
                pass
    except KeyboardInterrupt:
        # 手动中断时，尽量关闭 capture 并使用已收集的包
        try:
            capture.close()
        except Exception:
            pass
        if iter_packets is None:
            iter_packets = list(getattr(capture, '_packets', []))

    # 如果前面是一次性 sniff，iter_packets 已准备好，这里逐包处理并实时写入
    if iter_packets:
        for pkt in iter_packets:
            try:
                ts_dt = getattr(pkt, 'sniff_time', None)
                if not ts_dt:
                    ts = getattr(pkt, 'sniff_timestamp', '')
                    try:
                        ts_dt = datetime.fromisoformat(str(ts))
                    except Exception:
                        ts_dt = None

                src_ip, dst_ip = safe_get_ip(pkt)
                src_port, dst_port = safe_get_ports(pkt)
                proto = getattr(pkt, 'highest_layer', '') or getattr(pkt, '_ws.col.Protocol', '')
                length = safe_length(pkt)

                if ts_dt:
                    aggregator.add_packet(ts_dt, src_ip, src_port, dst_ip, dst_port, proto, length)
                    cutoff = ts_dt - timedelta(seconds=window_seconds)
                    flushed = aggregator.flush_older_than(cutoff)
                    for item in flushed:
                        writer.writerow([
                            item['timestamp'],
                            item['bytes_transferred'],
                            item['packet_count'],
                            item['connection_duration'],
                            item['source_port'],
                            item['destination_port'],
                            item['retransmission_rate'],
                            item['protocol'],
                            item['bytes_per_packet'],
                            item['packets_per_second'],
                        ])
                    out_f.flush()
                else:
                    continue
            except Exception:
                continue

    # 最后刷新剩余的窗口并关闭文件，确保最后一批数据也被写入
    remaining = aggregator.flush_all()
    for item in remaining:
        writer.writerow([
            item['timestamp'],
            item['bytes_transferred'],
            item['packet_count'],
            item['connection_duration'],
            item['source_port'],
            item['destination_port'],
            item['retransmission_rate'],
            item['protocol'],
            item['bytes_per_packet'],
            item['packets_per_second'],
        ])
    out_f.flush()
    out_f.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Capture network packets and export to CSV (requires tshark/pyshark).")
    parser.add_argument('--interface', required=True, help='Interface name (Windows: "Ethernet", "Wi-Fi" 等)')
    parser.add_argument('--duration', type=int, default=60, help='Capture duration in seconds (default 60)')
    parser.add_argument('--filter', dest='bpf', default='tcp or udp', help='BPF filter (default "tcp or udp")')
    # 默认不传 output 时，让脚本自动在 uploads 下生成带时间戳的文件
    parser.add_argument('--output', default='', help='Output CSV file (default: auto-generate under uploads/)')
    parser.add_argument('--max-packets', type=int, default=0, help='Max packets to capture (0 = not used)')
    parser.add_argument('--tshark-path', dest='tshark_path', default=None, help='Optional full path to tshark executable')
    args = parser.parse_args()

    capture_to_csv(args.interface, args.duration, args.bpf, args.output, args.max_packets, args.tshark_path)