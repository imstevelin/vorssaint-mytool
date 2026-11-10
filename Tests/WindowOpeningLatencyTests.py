#!/usr/bin/env python3
"""Opt-in native AX benchmark; requires a logged-in, unlocked, AX-trusted host.

Use --baseline=REF to compare the pre-fix production service. Temporary fixture
apps/preferences are isolated; no real app's geometry or saved profile changes.
"""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / 'Tests/Fixtures/WindowOpeningLatency'
SERVICE = 'Sources/Vorssaint/Services/WindowLayout/DisplayWindowMemoryService.swift'
OBSERVER = 'Sources/Vorssaint/Services/WindowLayout/DisplayWindowAXCache.swift'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline')
    parser.add_argument('--trace', action='store_true')
    parser.add_argument('--reconnect', action='store_true')
    args = parser.parse_args()
    def source(path):
        if args.baseline:
            return subprocess.check_output(['git', 'show', f'{args.baseline}:{path}'], cwd=ROOT, text=True)
        return (ROOT / path).read_text()
    with tempfile.TemporaryDirectory(prefix='window-opening-native-') as temp:
        temp = Path(temp)
        observer = source(OBSERVER)
        merge = ', mergingWindows: false' if 'mergingWindows:' in observer else ''
        observer += '''\nextension DisplayWindowEventObserver {
    func fixtureReady(pid: pid_t, completion: @escaping () -> Void) {
        queue.async { [self] in
            updateOnQueue([pid: []], replacingAll: false%s)
            DispatchQueue.main.async(execute: completion)
        }
    }
}\n''' % merge
        (temp / 'Observer.swift').write_text(observer)
        service = source(SERVICE)
        if args.trace:
            service = service.replace('self.eventVersions[pid, default: 0] += 1', 'trace("event created=\\(window != nil)"); self.eventVersions[pid, default: 0] += 1')
            service = service.replace('let openings = elements.compactMap', 'trace("opening query"); let openings = elements.compactMap')
            service = service.replace('// Cold title records', 'trace("opening results=\\(openings.count)"); // Cold title records')
            service = service.replace('processWindows(candidates, capturesLayout:', 'trace("opening candidates=\\(candidates.count)"); processWindows(candidates, capturesLayout:')
            service = service.replace('let resized = AXUIElementSetAttributeValue', 'trace("writing size"); let resized = AXUIElementSetAttributeValue')
            service += '\nfunc trace(_ text: String) { FileHandle.standardError.write(Data("[\\(ProcessInfo.processInfo.systemUptime)] \\(text)\\n".utf8)) }\n'
        service = service + '''\nextension DisplayWindowMemoryService {
    func fixtureStart(pid: pid_t, ready: URL) {
        syncWithPreferences()
        if CommandLine.arguments.contains("--reconnect") { pendingLayoutDisplays = Set(displayGeometry().keys) }
        windowEvents.fixtureReady(pid: pid) {
            WindowServerSnapshot.fixturePID = pid
            WindowServerSnapshot.hiddenUntil = ProcessInfo.processInfo.systemUptime+0.25
            try! Data().write(to: ready)
        }
    }
}\n'''
        (temp / 'Service.swift').write_text(service)
        controller = temp / ('WindowOpeningController-' + uuid.uuid4().hex)
        sdk = '/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk'
        if not Path(sdk).is_dir():
            sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
        sources = [temp / 'Service.swift', temp / 'Observer.swift', FIXTURES / 'Controller.swift']
        sources += [ROOT / p for p in [
            'Sources/Vorssaint/Services/WindowLayout/DisplayWindowMemorySupport.swift',
            'Sources/Vorssaint/Services/WindowLayout/DisplayWindowProfileStore.swift',
            'Sources/Vorssaint/Services/Switcher/AXWindowResolver.swift',
            'Sources/Vorssaint/Services/EnhancedUserInterfaceSuspension.swift']]
        subprocess.run(['swiftc', '-parse-as-library', '-sdk', sdk, '-o', str(controller), *map(str, sources)], check=True)
        bundle = temp / 'WindowFixture.app'
        executable = bundle / 'Contents/MacOS/WindowFixture'
        executable.parent.mkdir(parents=True)
        bundle_id = 'com.imstevelin.window-opening-fixture.' + uuid.uuid4().hex
        (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': bundle_id, 'CFBundleExecutable': 'WindowFixture',
            'CFBundleName': 'Window opening fixture', 'CFBundlePackageType': 'APPL', 'LSUIElement': True}))
        subprocess.run(['swiftc', '-parse-as-library', '-sdk', sdk, '-o', str(executable), str(FIXTURES / 'Window.swift')], check=True)
        ready = temp / 'ready'
        window = subprocess.Popen([str(executable), str(ready)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        control = subprocess.Popen([str(controller), str(window.pid), bundle_id, str(ready)] + (['--reconnect'] if args.reconnect else []), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            out, err = window.communicate(timeout=12)
            if window.returncode:
                raise RuntimeError(f'fixture failed ({window.returncode}): {out} {err}')
            result = json.loads(out)
            print(json.dumps({'source': args.baseline or 'working-tree', 'snapshot_lag_ms': 250, 'pending_reconnect_layout': args.reconnect, **result}))
            if not args.baseline and result['placement_ms'] >= 250:
                raise AssertionError('first placement waited for on-screen visibility instead of the AX creation handle')
        finally:
            for process in (window, control):
                if process.poll() is None:
                    process.terminate()
                logs, errors = process.communicate(timeout=5)
                if args.trace and process is control:
                    print(logs, errors)
            # The controller's fallback persistence has its own CLI domain.
            subprocess.run(['defaults', 'delete', controller.name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
