#!/bin/bash
DATE=`date +%Y/%m/%d:%H:%M`
WORK_DIR=/root/jungwon
LOG_FILE=$WORK_DIR/logs/log-$(date +%Y%m%d%H%M)_nas.txt
SRCIP=10.10.0.84
CONN=jungwon@$SRCIP
PW=accordionadmin

#### Pvc리스트 확인
echo "=== CHECK Pod LIST ===" 
printf "%-10s %-15s %-20s %-20s %-20s %-25s %10s\n" "NAMESPACE" "OWNERKIND" "OWERAAME" "POD" "CLAIMNAME" "PV" "SIZE(kb)" | tee -a $LOG_FILE
kubectl get pv -o json | jq -r --arg ip $SRCIP \
'.items[]|select(.status.phase=="Bound")|{name: .metadata.name, nfs: .spec.nfs.server, namespace:.spec.claimRef.namespace, claimName: .spec.claimRef.name, path: .spec.nfs.path}|select(.nfs==$ip)|[.claimName, .namespace, .name, .path] | @tsv'|
while IFS=$'\t' read -r claimName namespace pv path
do

### Pod 리스트 확인
kubectl -n $namespace get pod -o json | jq -r --arg pvc $claimName \
'.items[]|{metadata:.metadata , volumes:.spec.volumes}| select(.volumes[].persistentVolumeClaim.claimName==$pvc) | {name:.metadata.name, ownerKind: .metadata.ownerReferences[0].kind, owerName:.metadata.ownerReferences[0].name} | [.ownerKind, .owerName, .name] | @tsv' |
  while IFS=$'\t' read -r ownerKind owerName name
  do
    ## CHECK PV SIZE
    size=`sshpass -p $PW ssh $CONN du -sk $path 2> /dev/null | awk '{print $1}'`
    claimName=`echo $claimName | cut -c1-20`
    name=`echo $name | cut -c1-20`
    pv=`echo $pv | cut -c1-25`
    if [ $ownerKind = "ReplicaSet" ];then
    kubectl -n $namespace get rs $owerName -o json | jq -r --arg claimName ${claimName} \
    --arg name $name \
    --arg pv $pv \
    --arg size $size \
    '[.metadata.namespace, .metadata.ownerReferences[0].kind, .metadata.ownerReferences[0].name[0:19], $name, $claimName, $pv, $size]|@tsv' | \
    xargs printf "%-10s %-15s %-20s %-20s %-20s %-25s %10d\n" 
    else
    owerName=`echo $owerName | cut -c1-20`
    printf "%-10s %-15s %-20s %-20s %-20s %-25s %10d\n" $namespace $ownerKind $owerName $name ${claimName} $pv $size 
    fi 
  done
done  | tee -a $LOG_FILE