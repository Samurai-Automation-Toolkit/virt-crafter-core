# 📖 VirtCrafter Core — Installation Guide

Before you begin, make sure your system meets these requirements.

---

## ⚙️ System Requirements

Before you begin, ensure your system meets these requirements:

- 💻 **64-bit computer** with virtualization support enabled in the BIOS or UEFI
- 🧠 **At least 8 GB of RAM** (16 GB recommended if running other programs)
- 💾 **At least 50 GB of free disk space**
- 🌐 **Internet connection** (only once — to download the Rocky Linux ISO)

---

## 📦 Step 1: Install the Required Software

### For Ubuntu or Debian:

Run these commands in your terminal:
```bash
sudo apt update
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients virtinst curl python3
```

### For Rocky Linux, AlmaLinux, CentOS, or RHEL:

Run these commands:
```bash
sudo dnf install @virtualization virt-install libvirt curl python3
```

---

## 👤 Step 2: Add Your User to the Right Groups

Run this command to add your username to the groups that control virtual machines:
```bash
sudo usermod -a -G libvirt,kvm $USER
```

Then run this command to apply the changes immediately without logging out:
```bash
newgrp libvirt
```

### ✅ Verify It Worked

To check if it worked, type this command:
```bash
virsh list --all
```

If you see a list that says **"Id Name State"** — even if it's empty — then you're ready.

⚠️ If you see an error about **permission denied**, restart your computer and try again.

---

## 🔓 Optional: Allow virsh to Run Without sudo Password

To avoid being asked for a password during VM creation, run this command once:
```bash
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/virsh" | sudo tee /etc/sudoers.d/virt-crafter
```

### ✅ Test It
```bash
sudo virsh net-list --all
```

If no password is asked, it worked.

---

## 💿 Step 3: Download the Rocky Linux ISO

Go to this website and download the file:

🔗 [https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.6-x86_64-minimal.iso](https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.6-x86_64-minimal.iso)

Once the download is complete, find the file on your computer.

Now, open your **VirtCrafter Core** folder — the one you downloaded from GitHub.

Inside that folder, create a new folder called `iso` — if it doesn't exist already.

Move the downloaded `Rocky-9.6-x86_64-minimal.iso` file into that `iso` folder.

---

## ▶️ Step 4: Run the Script

Open your terminal.

Go to the folder where you downloaded **VirtCrafter Core**.

Make the launcher script executable by typing this:
```bash
chmod +x launcher.sh
```

Now run it:
```bash
bash launcher.sh
```

**That's it.**

---

## ⏳ What Happens Next?

The script will check your system, make sure everything is ready, and then start installing your virtual machine automatically.

You will see messages like:
- 💾 "Creating disk image"
- 📝 "Generating kickstart file"
- 🚀 "Starting VM installation"

**Wait quietly. Do not close the window.**

It will take between **5 and 15 minutes**.

---

## 🎉 Installation Complete

When it finishes, you will see a message like this:
```
🎉 VM 'virt-crafter-vm' created successfully!
Access via: virsh console virt-crafter-vm
SSH (after IP assigned): ssh ops@<vm-ip>
```

---

## 🔌 Step 5: Access Your New Virtual Machine

After the installation finishes, the VM will shut down automatically.

To turn it on and connect to it, use one of these two methods:

### Option 1: Connect Through the Console (text only)
```bash
virsh console virt-crafter-vm
```

### Option 2: Connect Through SSH

First, find the IP address by typing:
```bash
virsh net-dhcp-leases default
```

Look for the line that shows an IP address assigned to your VM — it will look like `192.168.122.x`

Then connect with:
```bash
ssh ops@192.168.122.x
```

### 🔑 Login Credentials

- **User password (ops):** `159Zxc753`
- **Root password:** `159Zxc753#`
- **Changeable:** Change the password and the hash in kickstart template and script use python on your terminal to get hash.
```
python3 -c "import crypt; print(crypt.crypt('159Zxc753', crypt.mksalt(crypt.METHOD_SHA512)))"
```

---

## ⚠️ Important Note About Passwords and Hashes

The passwords you see above are hardcoded into the system for simplicity — so you can get started instantly.  
But they are not the passwords you type — they are already **encrypted (hashed)** inside the installation file.

**This means:**
- ✅ You can type `159Zxc753` when SSH asks for the password — and it will work.
- ✅ You do **NOT** need to change the hash in the template.
- ✅ If you ever want to change the password later, just log in and type: `passwd`

**You do NOT need to generate your own password hash.**  
The script handles everything automatically.

---

## 🛠️ Step 6: Manage Your VM

### List All Virtual Machines
```bash
virsh list --all
```

### Start a Stopped VM
```bash
virsh start virt-crafter-vm
```

### Shut Down a VM
```bash
virsh shutdown virt-crafter-vm
```

### Delete a VM and Its Disk
```bash
virsh undefine virt-crafter-vm --remove-all-storage
```

---

## ✅ You're All Set!

You now have a fully working, clean, automated **Rocky Linux 9.6** virtual machine — with no prompts, no license keys, no hidden rules.

**This is open source. You own it. You can use it. You can share it.**

---

💙 **We built it for you. With love.**

— **Ahmad M. Waddah**