#!/usr/bin/env python3
"""Inject postinst script into a .deb package's control.tar archive."""
import tarfile
import io
import os
import sys
import gzip
import lzma

def main():
    if len(sys.argv) < 3:
        print("Usage: inject_postinst.py <deb_path> <postinst_path>")
        sys.exit(1)

    deb_path = os.path.abspath(sys.argv[1])
    postinst_path = os.path.abspath(sys.argv[2])
    deb_name = os.path.basename(deb_path)
    work_dir = os.path.dirname(deb_path)

    # Read postinst content
    with open(postinst_path, 'rb') as f:
        postinst_content = f.read()

    # Work in temp directory
    tmp_dir = '/tmp/deb_inject_work'
    if os.path.exists(tmp_dir):
        import shutil
        shutil.rmtree(tmp_dir)
    os.makedirs(tmp_dir)
    os.chdir(tmp_dir)

    # Extract .deb (ar archive)
    os.system(f'ar x "{deb_path}"')

    # Find control archive
    control_tar = None
    for f in os.listdir('.'):
        if f.startswith('control.tar'):
            control_tar = f
            break

    if not control_tar:
        print("ERROR: control.tar not found in .deb")
        sys.exit(1)

    print(f"Found control archive: {control_tar}")

    # Read and decompress control archive
    with open(control_tar, 'rb') as f:
        control_data = f.read()

    if control_tar.endswith('.gz'):
        tar_bytes = gzip.decompress(control_data)
        new_name = 'control.tar.gz'
        compress_fn = gzip.compress
    elif control_tar.endswith('.xz'):
        tar_bytes = lzma.decompress(control_data)
        new_name = 'control.tar.xz'
        compress_fn = lzma.compress
    elif control_tar.endswith('.lzma'):
        tar_bytes = lzma.decompress(control_data)
        new_name = 'control.tar.lzma'
        compress_fn = lambda d: lzma.compress(d, format=lzma.FORMAT_ALONE)
    else:
        tar_bytes = control_data
        new_name = 'control.tar'
        compress_fn = lambda d: d

    # Add postinst to tar archive
    new_buf = io.BytesIO()
    with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode='r') as tar:
        with tarfile.open(fileobj=new_buf, mode='w') as new_tar:
            # Copy existing members
            for member in tar.getmembers():
                new_tar.addfile(member, tar.extractfile(member))
            # Add postinst
            info = tarfile.TarInfo(name='./postinst')
            info.size = len(postinst_content)
            info.mode = 0o755
            info.type = tarfile.REGTYPE
            new_tar.addfile(info, io.BytesIO(postinst_content))

    new_tar_data = new_buf.getvalue()
    new_control_data = compress_fn(new_tar_data)

    # Write new control archive
    os.remove(control_tar)
    with open(new_name, 'wb') as f:
        f.write(new_control_data)

    # Find data archive(s)
    data_files = sorted([f for f in os.listdir('.') if f.startswith('data.tar')])

    # Repack .deb
    os.remove(deb_path)
    ar_cmd = f'ar rcs "{deb_name}" debian-binary {new_name} ' + ' '.join(f'"{d}"' for d in data_files)
    print(f"Running: {ar_cmd}")
    os.system(ar_cmd)

    # Move new .deb to original location
    if os.path.exists(deb_name):
        os.replace(deb_name, deb_path)
        print(f"Successfully added postinst to {deb_name}")
    else:
        print("ERROR: Failed to create new .deb")
        sys.exit(1)

if __name__ == '__main__':
    main()
