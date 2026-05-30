#!/usr/bin/env sh

ssh_port=33594
hostname=opencode

diod --listen 127.0.0.1:9566 --export /home/user/autocad-ballet --export /home/user/revit-ballet --no-auth 2>/dev/null
socat VSOCK-LISTEN:9566,fork TCP:127.0.0.1:9566 &
# ensure on host user has read-write access to /dev/vhost-vsock
# in guest: sudo crontab -e
# @reboot /usr/bin/socat TCP-LISTEN:9564,fork,reuseaddr VSOCK-CONNECT:2:9564 & sleep 1 && mount -t 9p -o trans=tcp,port=9564,uname=user,access=any,aname=/home/user/autocad-ballet 127.0.0.1 /home/user/autocad-ballet

passt -t $ssh_port --no-map-gw --vhost-user --socket /tmp/passt-$hostname --quiet

qemu-system-x86_64 -enable-kvm -smp 4 \
    -object memory-backend-memfd,id=mem,size=4096M,share=on \
    -machine memory-backend=mem \
    -drive file=/home/user/virtual-machines/$hostname.qcow2,if=virtio \
    -chardev socket,id=chr0,path=/tmp/passt-$hostname \
    -netdev vhost-user,id=net0,chardev=chr0 \
    -device virtio-net-pci,netdev=net0 \
    -device vhost-vsock-pci,guest-cid=5 \
    -device virtio-balloon-pci \
    -daemonize \
    -display none

until ssh -p $ssh_port user@127.0.0.1 'exit' 2>/dev/null; do sleep 1; done
ssh -p $ssh_port user@127.0.0.1
