#!/usr/bin/env sh

ssh_port=33591
hostname=claude
exec > /dev/null 2>&1

# slirp
passt -t $ssh_port --no-map-gw --vhost-user --socket /tmp/passt-$hostname

# 9p file server
diod --listen 127.0.0.1:9564 --export /home/user/autocad-ballet --export /home/user/revit-ballet --no-auth
socat VSOCK-LISTEN:9564,fork TCP:127.0.0.1:9564 &

qemu-system-x86_64 -enable-kvm -smp 8 \
    -object memory-backend-memfd,id=mem,size=4096M,share=on \
    -machine memory-backend=mem \
    -drive file=/home/user/virtual-machines/$hostname.qcow2,if=virtio \
    -chardev socket,id=chr0,path=/tmp/passt-$hostname \
    -netdev vhost-user,id=net0,chardev=chr0 \
    -device virtio-net-pci,netdev=net0 \
    -device vhost-vsock-pci,guest-cid=3 \
    -device virtio-balloon-pci \
    -daemonize \
    -display none

until ssh -p $ssh_port user@127.0.0.1 'exit'; do sleep 1; done

# autocad ballet relay chains
# for PORT in $(grep -v '^#' $HOME/autocad-ballet/runtime/network/sessions | grep -v '^$' | cut -d',' -f2); do
#     pgrep -f "socat VSOCK-LISTEN:$PORT" || TAG=autocad-ballet socat VSOCK-LISTEN:$PORT,fork TCP:127.0.0.1:$PORT &
#     ssh -p $ssh_port user@127.0.0.1 "( pgrep -f '^socat TCP-LISTEN:$PORT' || TAG=autocad-ballet socat TCP-LISTEN:$PORT,bind=127.0.0.1,reuseaddr,fork VSOCK-CONNECT:2:$PORT ) >/dev/null 2>&1 &"
# done

# revit ballet relay chains
for PORT in $(grep -v '^#' $HOME/revit-ballet/runtime/network/sessions | grep -v '^$' | cut -d',' -f2); do
    pgrep -f "socat VSOCK-LISTEN:$PORT" || TAG=revit-ballet socat VSOCK-LISTEN:$PORT,fork TCP:127.0.0.1:$PORT &
    ssh -p $ssh_port user@127.0.0.1 "( pgrep -f '^socat TCP-LISTEN:$PORT' || TAG=revit-ballet socat TCP-LISTEN:$PORT,bind=127.0.0.1,reuseaddr,fork VSOCK-CONNECT:2:$PORT ) >/dev/null 2>&1 &"
done

exec > /dev/tty 2>&1
ssh -p $ssh_port user@127.0.0.1
