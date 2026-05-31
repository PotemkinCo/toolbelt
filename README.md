# Toolsbelt 

## Ubuntu setup script
```bash
wget https://raw.githubusercontent.com/PotemkinCo/toolbelt/main/ubuntu_setup.sh && sudo bash ubuntu_setup.sh
```

For leaving ssh & ipv6 as is: 
```bash
wget https://raw.githubusercontent.com/PotemkinCo/toolbelt/main/ubuntu_setup.sh && sudo bash ubuntu_setup.sh -no-ssh -keep-ipv6
```

## FreeBSD nicies
```bash
curl -O "https://raw.githubusercontent.com/PotemkinCo/toolbelt/refs/heads/main/check_{all_bsd_disks,amd_cpu_backdoor}.sh" \
  && chmod +x check_{all_bsd_disks,amd_cpu_backdoor}.sh
```

## Notes:
- quick Docker install (`curl https://get.docker.com/ | sh`)
- gpg stream to rclone, without intermediate files ( [rclone ref]([url](https://forum.rclone.org/t/how-can-i-stream-to-a-remote/29754/2)), [gpg ref]([url](https://lists.gnupg.org/pipermail/gnupg-users/2008-December/035168.html)) )
