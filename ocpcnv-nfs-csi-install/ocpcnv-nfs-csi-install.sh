#!/bin/bash
# Instructions for CLI install of CNV at:
# https://docs.redhat.com/en/documentation/openshift_container_platform/4.15/html/virtualization/installing#installing-virt-operator-cli_installing-virt
# nfs-csi install at 
# https://hackmd.io/@johnsimcall/BJeW2Y5mT?utm_source=preview-mode&utm_medium=rec
# and others!

#==========================================================================================
# USER DEFINED PARAMETERS:
#==========================================================================================
#
# These four parameters can be user defined:
#
# NFSSERVER can be YOUR NFS server, else YAKKO will enable NFS on the YAKKO host and set this address up automatically
NFSSERVER=""     
#
# This is the directory offered for use on the NFS server. 
# If empty, YAKKO will create a share in the YAKKO folder with name $VMSTORAGENAME
# If not empty, it will be mounted from NFSSERVER, or will be created on the YAKKO host
NFSPATH=""
VMSTORAGENAME=vm-nfs-storage # ignored if the above is not blank. Change to your liking as above
#
# if you want to break up the install of OCPCNV by stages, change to N
AUTO=Y

# Examples?
# 1) Leave both blank and YAKKO will create a NFS share on the YAKKO host on BASENETWORK.1 
#    this is the YAKKO host as seen in the virtual network
# 2) NFSSERVER=192.168.1.10
#    NFSPATH=/mnt/openshiftvirtvms
#    The above indicates that you will be using YOUR NFS server 192.168.1.10 and there is an 
#    existing share already created at /mnt/openshiftvirtvms
#    NOTE that both have to exist if you are using your own NFS server. Refer to the below for setting up
# 3) NFSSERVER=""
#    NFSPATH=/mnt/myvms
#    YAKKO will create a NFS share on /mnt/myvms on the YAKKO host on BASENETWORK.1
#
#==========================================================================================

process-stage() {

	#$1 is wait time
	#$* is stage name
	WAITTIME=$1; shift
	STAGENAME=$*

	echo
	echo "--------------------------------------------------------------------"
	if [ "$AUTO"  == Y ]
	then
		echo "Proceeding with stage [$STAGENAME]"
		echo
		return 0
	fi

	while true
	do
		echo
		echo -n "Proceed with stage [$STAGENAME] [(Y)es/(N)o/(E)xit]? "
		read RESPONSE

		if [ "$RESPONSE" == "Y" ]
		then
			return 0
			break
		fi

		if [ "$RESPONSE" == "N" ]
		then
			return 1
			break
		fi

		if [ "$RESPONSE" == "E" ]
		then
			exit
		fi
	done

	sleep $WAITTIME
}


setup-nfs-provisioner() {
	# https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner#manually

	# Reference vars if you want to change the names
	NFS_STORAGE_CLASS_NAME=nfs-client # the test pod uses this name, so only change if not using it!!
	NFSNAMESPACE=nfs-provisioner

	if [ $# -ne 2 ]
	then
		echo
		echo "USAGE: $(basename $0) server path" 
		echo "       This script simplifies the configuration of a NFS provisioner and storage class"
		echo "       - progress --> will create all required assets in the indicated path  and proceed to configure"
		echo "                      if passed, server and path are the NFS resource to use on the nework"
		exit 1
	else
		NFS_SERVER=$1
		NFS_PATH=$2
	fi

	# First lets test the path!
	showmount -e ${NFS_SERVER} 2>/dev/null | grep "${NFS_PATH} " >/dev/null 
	if [ $? -eq 0 ]
	then
		echo
		echo "Path ${NFS_SERVER}:/${NFS_PATH} is available at the NFS server."
		echo "NOTE: This script does not check that the share has appropriate permssions"
		echo
	else
		echo "ERROR: Path ${NFS_SERVER}:/${NFS_PATH} does not appear to be exported."
		echo "       Check it and run again."
		exit
	fi

	echo
	echo "Adding nfs-csi HELP repo"
	# This is using HELM
	${HELM} repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
	# ${HELM} search repo -l csi-driver-nfs

	HELMCHARTVERSION=$(${HELM} search repo -l csi-driver-nfs | grep -v NAME | head --lines=1 | awk '{ print $2 }')

	echo
	echo "Running HELM nfs-csi install"
	if [ $(${OC} get nodes | grep -c master) -eq 3 ]
	then
		# This for a multinode cluster - need another section for SNO
		${HELM} install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --version ${HELMCHARTVERSION} \
		--create-namespace \
		--namespace csi-driver-nfs \
		--set controller.runOnControlPlane=true \
		--set controller.replicas=2 \
		--set controller.strategyType=RollingUpdate \
		--set externalSnapshotter.enabled=true \
		--set externalSnapshotter.customResourceDefinitions.enabled=false
	else
		# SNO or single master 
		${HELM} install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --version ${HELMCHARTVERSION} \
		--create-namespace \
		--namespace csi-driver-nfs \
		--set controller.replicas=1 \
		--set controller.runOnControlPlane=true \
		--set externalSnapshotter.enabled=true \
		--set externalSnapshotter.customResourceDefinitions.enabled=false
	fi
	${OC} adm policy add-scc-to-user privileged -z csi-nfs-node-sa -n csi-driver-nfs
	${OC} adm policy add-scc-to-user privileged -z csi-nfs-controller-sa -n csi-driver-nfs
}

# ========================================================================
# THE INSTALLER STARTS HERE 
# ========================================================================

# a couple of simple checks

if [ "$#" -ne 0  ]
then 
	echo
	echo "USAGE $0 [NFS-PATH [NFS-SERVER]]"
	echo "      if not provided, NFS-SERVER will be resolved as the YAKKO host in the virtual network"
	echo "      and NFS-PATH will default to 'YAKKO-DIR/$NFSPATH"
	echo
	exit 1
fi

# We search for an oc that's mostly up to date within the YAKKO dir - or not
OC=$(find . -name oc | head -n 1)
if [ -z "${OC}" ] 
then
	OC=$(which oc)
	if [ $? -ne 0 ]
	then
		echo "'oc' command not available"
		exit 1
	fi
fi

if [ -z "$NFSSERVER" ]
then
	if [ -z ".yakkohome" ] 
	then
		echo "ERROR: Automated installation depends on a cluster built with YAKKO"
		echo "       Edit NFSSERVER at the top for your own NFS server"
		exit 1
	fi

	if [ -z "$NFSPATH" ]
	then
		# The VM dir will be setup on the YAKKO directory
		NFSPATH=$(realpath .)/${VMSTORAGENAME}
	fi

	NFSSERVER=$(cat .lastclusterbuild | grep BASENETWORK | cut -f2 -d=).1

	echo
	echo "- NFS Path has been configured as $NFSPATH"
	echo "- NFS Server has been configured as $NFSSERVER"
	process-stage 1 "Setup YAKKO host NFS share" && ./yakko infra nfsshare $NFSPATH 
else
	if [ -z "NFSPATH" ]
	then
		echo "ERROR: You have configured an NFS server without specifying a path"
		exit
	fi 
	echo "- NFS Path has been configured as $NFSPATH"
	echo "- NFS Server has been configured as $NFSSERVER"
fi

process-stage 1 "Cluster Login" && {
	if [ -x ./cluster-login ]
	then 
		./cluster-login
	else
		${OC} login
	fi
}	

process-stage 10 "Install HELM binary" && {
	if [ ! -x /usr/local/bin/helm ]
	then
		curl -L https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/helm-linux-amd64 -o /usr/local/bin/helm
		[ $? -ne 0 ] && { 
			echo "Failed to install helm, cannot continue!"
			exit
		}
	fi
	HELM=/usr/local/bin/helm
	chmod +x ${HELM}
}

process-stage 5 "NFS Provisioner" && setup-nfs-provisioner $NFSSERVER $NFSPATH

process-stage 5 "Setup Storage class" && 
	${OC} apply -f - <<HEREDOC
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: nfs.csi.k8s.io
parameters:
  server: ${NFSSERVER}
  share:  ${NFSPATH}
  subDir: \${pvc.metadata.namespace}-\${pvc.metadata.name}-\${pv.metadata.name}  ### Folder/subdir name template
reclaimPolicy: Delete
volumeBindingMode: Immediate
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: nfs-snapclass
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: nfs.csi.k8s.io
deletionPolicy: Delete
parameters:
HEREDOC


process-stage 20 "Subscribe OCP CNV Operator" && {
${OC} apply -f - <<HEREDOC
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cnv
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
    - openshift-cnv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: hco-operatorhub
  namespace: openshift-cnv
spec:
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  name: kubevirt-hyperconverged
  startingCSV: kubevirt-hyperconverged-operator.v4.15.2
  channel: "stable" 
HEREDOC

	while true 
	do
		${OC} get csv -n openshift-cnv 2>/dev/null | grep "Succeeded" > /dev/null
		[ $? -eq 0 ] && break
		sleep 10
	done
}

process-stage 30 "Deploy OCP CNV/HyperConverged Instance" && {
	${OC} apply -f - <<HEREDOC
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
HEREDOC

	while true 
	do
		${OC} events HyperConverged kubevirt-hyperconverged -n openshift-cnv | grep "Created container virt-handler" > /dev/null
		[ $? -eq 0 ] && break
		sleep 10
	done
	sleep 30
}

process-stage 5 "Patch storageprofile clone strategy" && 
	${OC} patch storageprofile nfs-csi --type merge -p '{"spec":{"cloneStrategy": "csi-clone"}}'

process-stage 30 "Install Hostpath Provisioner (HPP)" && ${OC} apply -f - <<HEREDOC
apiVersion: hostpathprovisioner.kubevirt.io/v1beta1
kind: HostPathProvisioner
metadata:
  name: hostpath-provisioner
spec:
  imagePullPolicy: IfNotPresent
  storagePools: 
  - name: cnv-host-path 
    path: "/var/cnv-volumes" 
workload:
  nodeSelector:
    kubernetes.io/os: linux
HEREDOC

process-stage 60 "Install Hostpath CSI" && ${OC} apply -f - <<HEREDOC
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hostpath-csi
provisioner: kubevirt.io.hostpath-provisioner
reclaimPolicy: Delete 
volumeBindingMode: WaitForFirstConsumer 
parameters:
  storagePool: cnv-host-path
HEREDOC


