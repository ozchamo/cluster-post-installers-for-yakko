
This script automates the installation of OpenShift Virtualisation using NFS as the storage provider with automatic setup.

USER DEFINED PARAMETERS:

These four parameters can be user defined:

- NFSSERVER: can be YOUR NFS server. If left BLANK YAKKO will enable NFS on the YAKKO host and set this address up automatically from the virtual IP of the YAKKO HOST.
- NFSPATH: This is the directory offered for use on the NFS server. If left BLANK, YAKKO will create a share in the YAKKO folder with name $VMSTORAGENAME.
- VMSTORAGENAME: this is the directory name that nfs-csi will use if YAKKO sets all up automatically, which will only happen if both the above parameters are left blank. The default name is "vm-nfs-storage"
- AUTO: If you want to break up the install of OCP VIRT and the nfs-csi driver in stages, set to Y (which is the default)

Examples:
- BYO NFS Server:
  NFSSERVER=192.168.1.10
  NFSPATH=/mnt/openshiftvirtvms
  The above indicates that you will be using YOUR NFS server 192.168.1.10 and there is an existing share already created at /mnt/openshiftvirtvms. NOTE that both have to exist if you are using your own NFS server. YAKKO plays no part in this setup.

- Use YAKKO's automatic ability to create, share and run an NFS server/share on the YAKKO host:
  NFSSERVER=
  NFSPATH=
  Leave both blank and YAKKO will create a NFS share on the YAKKO host in the virtual network, where the directory for NFS concontent will be in the the same directory YAKKO exists.

- Use YAKKO's automatic ability to create, share and run an NFS server/share on the YAKKO host, where you specify where you want the share to reside:
  NFSSERVER=
  NFSPATH=/mnt/myvms
  YAKKO will create an NFS share on /mnt/myvms on the YAKKO host in the virtual network (VMSTORAGENAME will be ignored)


