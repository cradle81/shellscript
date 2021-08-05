#SRCIP=10.20.200.210
#TARGETIP=10.20.200.170
SRCIP=10.20.200.170
TARGETIP=10.20.200.210

WORKDIR=.
APPYAML=$WORKDIR/appyaml
PVCYAML=$WORKDIR/pvcyaml
PVYAML=$WORKDIR/pvyaml
LIST_FILE=$WORKDIR/list.txt
WRL_FILE=$WORKDIR/workload.txt

NS=accordion
NFS_PVN=monitoring-data-provisioner
NFS_CONF=nfs-config


if [ ! -d $APPYAML ];then
mkdir -p $APPYAML
fi
if [ ! -d $PVCYAML ];then
mkdir -p $PVCYAML
fi
if [ ! -d $PVYAML ];then
mkdir -p $PVYAML
fi


# SRCIP를 가지고 있는 PV리스트 확인
## Bound된 pv만 Check
echo "=== CHECK PV LIST ==="
printf "%-20s %-25s %-50s\n" "NAMESPACE" "CLAIMNAME" "PVNAME"
kubectl get pv -o json | jq -r --arg ip $SRCIP \
'.items[]|select(.status.phase=="Bound")|{name: .metadata.name, nfs: .spec.nfs.server, namespace:.spec.claimRef.namespace, claimName: .spec.claimRef.name}|select( .nfs==$ip)|[.name, .claimName, .namespace] | @tsv ' |
while read -r name claimName namespace
do
printf "%-20s %-25s %-50s\n" $namespace $claimName $name
kubectl get pv $name -o yaml > $PVYAML/${namespace}_${name}.yaml
done 


#### Pvc리스트 확인
echo "=== CHECK Pod LIST ==="
printf "%-20s %-25s %-50s %-30s\n" "NAMESPACE" "OWNERKIND" "OWERAAME" "CLAIMNAME"
kubectl get pv -o json | jq -r --arg ip $SRCIP \
'.items[]|select(.status.phase=="Bound")|{name: .metadata.name, nfs: .spec.nfs.server, namespace:.spec.claimRef.namespace, claimName: .spec.claimRef.name}|select(.nfs==$ip)|[.claimName, .namespace] | @tsv'|
while IFS=$'\t' read -r claimName namespace
do
kubectl -n $namespace get pvc $claimName -o yaml > $PVCYAML/${namespace}_${claimName}.yaml

### Pod 리스트 확인
kubectl -n $namespace get pod -o json | jq -r --arg pvc $claimName \
'.items[]|{metadata:.metadata , volumes:.spec.volumes}| select(.volumes[].persistentVolumeClaim.claimName==$pvc) | {name:.metadata.name, ownerKind: .metadata.ownerReferences[0].kind, owerName:.metadata.ownerReferences[0].name} | [.ownerKind, .owerName, .name] | @tsv' |
  while IFS=$'\t' read -r ownerKind owerName name
  do
    if [ $ownerKind = "ReplicaSet" ];then
    kubectl -n $namespace get rs $owerName -o json | jq -r --arg claimName ${claimName} '[.metadata.namespace, .metadata.ownerReferences[0].kind, .metadata.ownerReferences[0].name, $claimName]|@tsv' | \
    xargs printf "%-20s %-25s %-50s %-30s\n" 
    else
    printf "%-20s %-25s %-50s %-30s\n" $namespace $ownerKind $owerName ${claimName}
    fi 
  done
done  | tee  list.txt

### Deployment, Statuefull, DeamonSet 확인후 저장

### monitoring alertmanager, prometheus kind화인  == monitoring 



echo "=== SAVE WordLoad ==="
printf "%-20s %-25s %-30s %-5s\n" "NAMESPACE" "KIND" "NAME" "REPLICAS"
awk '{print $1, $2, $3}' $LIST_FILE | uniq |
while read -r ns kind name 
do
#printf "%-20s %-25s %-50s \n" $ns $kind $name
#kubectl -n $ns get $kind $name -o yaml > $APPYAML/${ns}_${kind}_${name}.yaml
#kubectl -n $ns get $kind $name -o json | jq -r '[.metadata.namespace, .kind, .metadata.name, .spec.replicas] |@tsv' | xargs printf "%-20s %-25s %-50s %-30s\n"
kubectl -n $ns get $kind $name -o json | jq -r '[.metadata.namespace, .kind, .metadata.name, .spec.replicas] |@tsv' | xargs printf "%-20s %-25s %-50s %-30s\n"

done | tee $WRL_FILE

### WorkLoad Scale set 0 ####

echo "=== WorkLoad Replicas set 0 ==="
echo "== WorkLoad Replicas set 0 in monitor namespace ##"
echo "== WorkLoad Replicas set 0  in the other namespaces ##"

kubectl get alertmanagers.monitoring.coreos.com main  -n monitoring -o json | jq '.spec.replicas=0' | kubectl apply -f -
kubectl get Prometheus acc-prometheus-operator-prometheus  -n monitoring -o json | jq '.spec.replicas=0' | kubectl apply -f -

while read -r ns kind name replicas
do
printf "%-20s %-25s %-50s replicas ===> 0 \n" $ns $kind $name
kubectl -n $ns scale $kind $name --replicas=0
done < $WRL_FILE



## DELETE PVC ##
echo "=== DELETE PVC ==="
kubectl delete -f $PVCYAML

## DELETE PV ##
echo "=== DELETE PV ==="
kubectl delete -f $PVYAML


## PV IP 변경
echo "=== Chang NFS Server IP in PV ==="
perl -pi -e "s/server: $SRCIP$/server: $TARGETIP/g" $PVYAML/*
grep -r "server: " $PVYAML


## CREATE PV ##
echo "=== CREATE PV ==="
for file in `find $PVYAML -name "*.yaml" `
do 
echo $file
kubectl create -f $file --dry-run=client -o json | jq -r 'del(.spec.claimRef)' | kubectl create -f -
done

## CREATE PVC ##
echo "=== CREATE PVC ==="
kubectl create -f $PVCYAML



### WorkLoad Restore Replicas ###
echo "=== WorkLoad Restore Replicas  ==="
echo "== WorkLoad Restroe Repliicas in monitor namespace ##"
kubectl get alertmanagers.monitoring.coreos.com main  -n monitoring -o json | jq '.spec.replicas=1' | kubectl apply -f -
kubectl get Prometheus acc-prometheus-operator-prometheus  -n monitoring -o json | jq '.spec.replicas=1' | kubectl apply -f -

echo "== WorkLoad Restroe Repliicas in the other namespaces ##"
while read -r ns kind name replicas
do
printf "%-20s %-25s %-50s replicas ===> %s \n" $ns $kind $name $replicas
kubectl -n $ns scale $kind $name --replicas=$replicas
done < $WRL_FILE



## nfs provisioner 변경 IP변경
echo "=== Replace nfs provisioner: $NFS_PVN  ==="
kubectl -n $NS  get deployment $NFS_PVN -o json |jq --arg ip $TARGETIP '.spec.template.spec.containers[0].env[1].value=$ip' | kubectl replace -f -
kubectl -n $NS  get deployment $NFS_PVN -o json | jq '.spec.template.spec.containers[0].env[]'


## nfs-config 변경 
echo "=== Replace configmap $NFS_CONF ==="
kubectl get cm $NFS_CONF -n $NS -o yaml | sed "s/$SRCIP/$TARGETIP/g"| kubectl apply -f -
kubectl get cm $NFS_CONF -n $NS -o yaml | grep nfs.server



