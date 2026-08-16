# A Direct Ethernet Link to a Test Board

Wifi is fine for logging in, but slow for pushing a repo or pulling test
output. A cable straight from the laptop to the board is roughly ten times
faster and adds no infrastructure — no router, no DHCP server.

Measured between this laptop and the Pi 400 (100 MB over `scp`):

| | latency | 100 MB transfer |
|---|---|---|
| wifi | ~16 ms | 35.4 s |
| direct ethernet | ~2 ms | 3.2 s |

Both ends keep wifi for internet. The cable carries only traffic between the
two machines.

## The idea

Give each end a static address on a subnet nobody else uses, and tell both
ends never to treat that link as a default route.

    laptop   10.10.0.1/24
    board    10.10.0.2/24

**Choose the subnet by elimination.** Ours avoids `192.168.2.x` (home wifi),
`192.168.1.x` (a work bench setup), `10.0.0.x` (a board-to-board link in
another project), `172.17-18.x` (docker), `100.x` (tailscale) and `10.42.x`
(NetworkManager's own "shared connection" default). List what is already in
use before picking:

    ip -4 route
    nmcli -t -f NAME,TYPE connection show

## Pinning the profile to one adapter

If the laptop side is a **USB ethernet adapter**, this is worth knowing: the
interface is named after the adapter's MAC — `enx` + the address with the
colons removed. A different adapter is therefore a *different interface*, and
a profile can be pinned to one specific adapter so it can never activate on
another:

    cat /sys/class/net/<iface>/address       # e.g. 6c:6e:07:51:0c:75
    # -> interface enx6c6e07510c75

That is what makes this safe to set up on a laptop that also plugs into other
wired networks: the profile below binds to a MAC, so an adapter used elsewhere
never matches it, whatever it ends up being called.

## Laptop side

    nmcli connection add type ethernet con-name pi400-eth ifname enx6c6e07510c75 \
      802-3-ethernet.mac-address 6C:6E:07:51:0C:75 \
      ipv4.method manual ipv4.addresses 10.10.0.1/24 ipv4.never-default yes \
      ipv6.method disabled \
      connection.autoconnect yes connection.autoconnect-priority 10

    nmcli connection up pi400-eth

No `sudo` was needed — polkit allows an active local user to manage
connections.

## Board side

Raspberry Pi OS trixie uses NetworkManager, so the same tool works. (The
`90-NM-*.yaml` files under `/etc/netplan/` are first-boot leftovers from the
imager; new profiles are written to
`/etc/NetworkManager/system-connections/` instead.)

    sudo nmcli connection add type ethernet con-name laptop-eth ifname eth0 \
      ipv4.method manual ipv4.addresses 10.10.0.2/24 ipv4.never-default yes \
      ipv6.method disabled \
      connection.autoconnect yes connection.autoconnect-priority 10

    sudo nmcli connection up laptop-eth

## The two flags that matter

- **no gateway, plus `ipv4.never-default yes`** on both ends. Without this the
  direct link can install a default route and take over from wifi, cutting the
  machine off from the internet. Verify afterwards that `ip -4 route` still
  shows `default via ... dev <wifi>` on *both* machines.
- **`connection.autoconnect-priority`** higher than any existing DHCP profile
  for the same interface. Keeping the DHCP profile around means the adapter can
  still be used on an ordinary network with
  `nmcli con up "Wired connection 1"`.

## ssh

A second host entry, so either path can be chosen explicitly:

    Host pi400-eth
        HostName 10.10.0.2
        User pi
        IdentityFile ~/.ssh/pi400_ed25519
        IdentitiesOnly yes

`ssh pi400` still goes over wifi; `ssh pi400-eth` goes over the cable. Having
both is useful — if the cable is unplugged, the wifi name still works.

## Checking it

    ping -c3 -I <iface> 10.10.0.2         # from the laptop
    ip -4 route | grep '^default'         # must still be the wifi device
    ssh pi400-eth 'ip -4 route get 10.10.0.1'

Both profiles set `autoconnect yes` and are stored under
`/etc/NetworkManager/system-connections/`, so the link comes back by itself
after a reboot on either end.
