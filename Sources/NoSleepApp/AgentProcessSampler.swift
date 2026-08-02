import Foundation
import Darwin
import NoSleepCore

/// Real process sampler: executable path + cumulative CPU time for every
/// visible process, via libproc. CPU time comes from proc_pid_rusage, whose
/// ri_user_time/ri_system_time are in mach absolute-time units and need the
/// timebase to convert to seconds.
final class AgentProcessSampler: ProcessActivitySampling {
    private static let machToSeconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    func sampleProcesses() -> [ProcessSample] {
        var pids = [pid_t](repeating: 0, count: 8192)
        let byteCount = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard byteCount > 0 else { return [] }
        let count = min(Int(byteCount) / MemoryLayout<pid_t>.size, pids.count)

        var samples: [ProcessSample] = []
        samples.reserveCapacity(count)
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let command = String(cString: path)

            var usage = rusage_info_current()
            let ok = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) == 0
                }
            }
            guard ok else { continue }
            let cpuSeconds = Double(usage.ri_user_time &+ usage.ri_system_time)
                * Self.machToSeconds
            samples.append(ProcessSample(pid: pid, command: command, cpuTime: cpuSeconds))
        }
        return samples
    }
}
