# How to access LUKS encrypted drive from MAC

Mac OS does not natively support mounting LUKS encrypted drives. We can however use `https://github.com/AlexSSD7/linsk` to access an encrypted drive.

## Installation

```
$ brew install qemu
$ go install github.com/AlexSSD7/linsk@latest
```

## Access

1. First list all drives to find the correct drive
```
❯ diskutil list
...
/dev/disk4 (external, physical):
```

2. List partitions of the drive
```
❯ sudo linsk ls dev:/dev/disk4
...
NAME    SIZE FSTYPE      LABEL
vda       1G
├─vda1  300M ext4
├─vda2  256M swap
└─vda3  467M ext4
vdb     3.6T
└─vdb1  3.6T crypto_LUKS mnt_luks_20241225 <------------ this is the encrypted drive
...
```

3. Attach to the encrypted drive
```
❯ sudo linsk run dev:/dev/disk4 --l vdb1 --debug-shell
...
time=2024-12-25T14:46:58.744-05:00 level=INFO msg="Attempting to open a LUKS device" caller=file-manager vm-path=/dev/vdb1
Enter Password: <---------------------- Enter drive password

...
===========================
[Network File Share Config]
The network file share was started. Please use the credentials below to connect to the file server.

Type: AFP
URL: afp://127.0.0.1:9000/linsk
Username: linsk
Password: SOME_PASSWORD
===========================
...

localhost:~#
```

4. Change mount ownership to enable write perms when attaching the network share

```
# still in the debug shell
localhost:~# chown -R linsk:linsk /mnt
```

5. Attach the `afp` share to the mac and read/write files.
