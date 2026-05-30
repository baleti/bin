#!/usr/bin/env sh

port=33593
hostname=llama

passt -t $port:$port --vhost-user --socket /tmp/passt-$hostname --quiet

qemu-system-x86_64 -enable-kvm -smp 16 \
    -object memory-backend-memfd,id=mem,size=72G,share=on \
    -machine memory-backend=mem \
    -drive file=/home/user/virtual-machines/$hostname.qcow2,if=virtio \
    -chardev socket,id=chr0,path=/tmp/passt-$hostname \
    -netdev vhost-user,id=net0,chardev=chr0 \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-balloon-pci \
    -daemonize \
    -display none

until ssh -p $port user@127.0.0.1 'exit' 2>/dev/null; do sleep 1; done
ssh -p $port user@127.0.0.1
