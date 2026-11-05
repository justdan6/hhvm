#!/usr/bin/env python3
"""Export the actual native Linux HHVM binary, loader and library closure."""
import argparse
import hashlib
import json
import platform
import re
import shutil
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-root', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    binary = args.work_root / 'hhvm/hphp/hhvm/hhvm'
    machine = platform.machine()
    elf_machine = {'x86_64': 62, 'aarch64': 183}[machine]
    architecture = {'x86_64': 'x86_64', 'aarch64': 'arm64'}[machine]
    out = args.output
    if out.exists() and any(out.iterdir()):
        parser.error('--output must be empty, to avoid mixing builds')
    lib = out / 'lib'
    licenses = out / 'licenses'
    lib.mkdir(parents=True, exist_ok=True)
    licenses.mkdir(exist_ok=True)
    ldd = subprocess.check_output(['ldd', str(binary)], text=True)
    if 'not found' in ldd:
        raise SystemExit(ldd)
    dependencies = {}
    for line in ldd.splitlines():
        match = re.search(r'=>\s+(/\S+)', line) or re.match(r'\s*(/\S+)\s+\(', line)
        if match:
            path = Path(match[1])
            dependencies[path.name] = path.resolve()

    manifest = []
    def copy_elf(source, destination):
        with source.open('rb') as stream:
            header = stream.read(20)
        if (header[:6] != b'\x7fELF\x02\x01' or
                int.from_bytes(header[18:20], 'little') != elf_machine):
            raise SystemExit(f'Wrong ELF architecture: {source}')
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        with destination.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        manifest.append({'file': str(destination.relative_to(out)),
                         'source': str(source), 'sha256': digest,
                         'bytes': destination.stat().st_size})
    for name, source in sorted(dependencies.items()):
        copy_elf(source, lib / name)
    copy_elf(binary, out / 'hhvm')
    copy_elf(Path('/usr/bin/patchelf'), out / 'tools/patchelf')

    magick = args.work_root / 'installed/ImageMagick6'
    for relative in ['etc/ImageMagick-6', 'share/ImageMagick-6']:
        source = magick / relative
        if source.is_dir():
            shutil.copytree(source, out / relative)
    for source in (magick / 'lib').glob('ImageMagick-*'):
        if source.is_dir():
            shutil.copytree(source, lib / source.name)
    for name in ['hhvm-run', 'smoke.hack', 'imagick-smoke.hack']:
        shutil.copy2(Path(__file__).resolve().parent / name, out / name)

    owners = subprocess.run(['dpkg-query', '-S', *map(str, dependencies.values()),
                             '/usr/bin/patchelf'], text=True, capture_output=True)
    packages = {line.split(': /', 1)[0].split(':')[0]
                for line in owners.stdout.splitlines() if ': /' in line}
    if packages:
        versions = subprocess.check_output(['dpkg-query', '-W',
            '-f=${binary:Package}\t${Version}\n', *sorted(packages)], text=True)
        (out / 'library-packages.tsv').write_text(versions)
    for package in packages:
        notice = Path('/usr/share/doc') / package / 'copyright'
        if notice.is_file():
            shutil.copy2(notice, licenses / f'{package}.copyright')
    roots = [args.source, *(args.work_root / 'getdeps/release-train-src').glob('*')]
    for parent in [args.work_root / 'getdeps/extracted', args.work_root / 'sources']:
        if parent.is_dir():
            for source in parent.iterdir():
                if source.is_dir():
                    roots.append(source)
                    roots.extend(p for p in source.iterdir() if p.is_dir())
    for source in roots:
        for pattern in ['LICENSE*', 'COPYING*', 'NOTICE*', 'Copyright*']:
            for notice in source.glob(pattern):
                if notice.is_file():
                    destination = licenses / source.name / notice.name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(notice, destination)

    (out / 'manifest.json').write_text(json.dumps({
        'commit': args.commit, 'architecture': architecture,
        'version': subprocess.check_output([str(binary), '--version'], text=True),
        'files': manifest,
    }, indent=2) + '\n')
    (out / 'ldd-original.txt').write_text(ldd)
    (out / 'README.txt').write_text(
        f'HHVM Linux {architecture}; source commit {args.commit}\n'
        'Run ./hhvm-run --version or ./hhvm-run program.hack.\n'
        'First launch creates a private relocated copy of hhvm in this directory;\n'
        'allow write access and additional space equal to the binary size.\n'
        'The original hhvm remains unchanged. Moving the bundle regenerates the copy.\n'
        'The loader and libraries are bundled; system CA certificates, timezone\n'
        'data and kernel interfaces come from the host. See licenses/ and manifest.json.\n'
        'Docker Desktop x86 translation may need EVENT_NOEPOLL=1.\n'
        'Source and build instructions: https://github.com/justdan6/hhvm\n')
    print(f'Exported {architecture}: {len(dependencies)} libraries to {out}')


if __name__ == '__main__':
    main()
