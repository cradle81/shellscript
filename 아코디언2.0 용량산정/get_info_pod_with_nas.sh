#!/bin/bash
## 특정 Namespace만 체크##
## 
DATE=`date +%Y/%m/%d:%H:%M`
WORK_DIR=/root/jungwon
LOGFILE=$WORK_DIR/logs/log-$(date +%Y%m%d%H%M)_pod_nas.txt
SRCIP=10.10.0.84
CONN=jungwon@$SRCIP
PW=accordionadmin

## POD LIST ##
## 러닝 상태만 체크

kubectl get pod -A -o wide |grep Running| awk '{printf "%-30s %-40s %-20s\n", $1,$2,$8}' | sort | grep -v NAMESPACE>  $WORK_DIR/list.txt 

## 각 노드의 crictl 실행
## keygen으로 ssl copy가 되어야 함
for node in `kubectl get nodes | grep -v NAME | awk '{print $1}'`
do
ip=`kubectl get node -o wide |grep -v INTERNAL-IP | grep $node | awk '{print $6}'`
ssh root@$ip "crictl stats " > $WORK_DIR/$node.stats
ssh root@$ip "crictl ps " > $WORK_DIR/$node.ps
ssh root@$ip "crictl images " > $WORK_DIR/$node.images
done

#echo HEAD
printf "%-20s %-15s %-20s %-40s %-20s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s \n" "DATE" "NAMESPACE" "APP" "POD" "CONNAME" "CPU(m)" "CPU(%)" "MEM(MB)" "DISK" "NAS_SIZE" "REQCPU" "REQMEM" "IMAGESIZE" | tee $LOGFILE

while read line
do 
NS=`echo $line| awk '{print $1}'`
POD=`echo $line| awk '{print $2}'`
NODE=`echo $line | awk '{print $3}'`

#container count

#kubectl get pod $POD -n $NS -o json | jq -r ".spec.containers[].name" > conlist.txt
kubectl get pod $POD -n $NS -o json | jq -r '.status.containerStatuses[]|"\(.name), \(.containerID)"' > $WORK_DIR/conlist.txt
NODE_NAME=`kubectl get pod $POD -n $NS -o json | jq -r ".spec.nodeName"`

while read con
do

CON_ID=`echo $con | awk -F'//' '{print $2}' | cut -c1-13`
CON_NAME=`echo $con | awk -F',' '{print $1}'`
APP=`kubectl get pod $POD -n $NS -o json | \
kubectl get pod $POD -n $NS -o json | \
jq -r '{name:.metadata.name, ownerKind: .metadata.ownerReferences[0].kind, owerName:.metadata.ownerReferences[0].name}|[.ownerKind, .owerName, .name]| @csv' | tr -d '"' | \
while IFS=',' read -r ownerKind owerName name
do
if [ "$ownerKind" = "ReplicaSet" ];then
kubectl get rs $owerName -n $NS -o json | jq -r '[.metadata.ownerReferences[0].name]|@tsv' | cut -c1-20
elif [ "$ownerKind" = "" ];then
echo "None"
else
echo $owerName | cut -c1-20
fi
done`


REQCPU=`kubectl get pod $POD -n $NS -o json | jq -r --arg con $CON_NAME '.spec.containers[]|select(.name==$con)|.resources.requests|.cpu//0'`
REQMEM=`kubectl get pod $POD -n $NS -o json | jq -r --arg con $CON_NAME '.spec.containers[]|select(.name==$con)|.resources.requests|.memory//0'`

CPU=`kubectl top pod $POD -n $NS --containers | awk -v con=$CON_NAME '{if(con==$2)print substr($3,1,length($3)-1)}'`
CPU2=`grep $CON_ID $WORK_DIR/$NODE_NAME.stats | awk '{print $2}'`

MEM=`grep $CON_ID $WORK_DIR/$NODE_NAME.stats | awk '{if($3 ~ /GB/){printf "%s\n", substr($3,1,length($3)-2)*1024}else if($3 ~ /kB/){print substr($3,1,length($3)-2)/1024}else {print substr($3,1,length($3)-2)}}'`

DISK=`grep $CON_ID $WORK_DIR/$NODE_NAME.stats | awk '{print $4}'`
IMAGE_ID=`grep $CON_ID $WORK_DIR/$NODE_NAME.ps | awk '{print $2}'`
##동일한 이미지가 있을 수 있음
IMAGESIZE=`grep $IMAGE_ID $WORK_DIR/$NODE_NAME.images | awk '{print $4}'|uniq`


nas_size=0
for pvc in `kubectl -n $NS get pod $POD -o json | \
jq -r '[.spec.volumes[]|select(has("persistentVolumeClaim")).persistentVolumeClaim.claimName]|@tsv'`
do
 pv=`kubectl get pvc $pvc -n $NS -o json | jq -r '[.spec.volumeName]|@tsv'`
 path=`kubectl get pv $pv -n $NS -o json | jq -r \
 --arg ip $SRCIP 'select(.spec.nfs.server==$ip)|[.spec.nfs.path]|@tsv'`
 nas_size=`sshpass -p $PW ssh $CONN du -sk $path 2> /dev/null | awk '{print $1}'`
done



#echo  $IMAGE $IMAGESIZE

printf "%-20s %-15s %-20s %-40s %-20s %-10s %-10s %-10s %-10s %-10s %-10s %-10s %-10s \n" $DATE ${NS:0:14} $APP ${POD:0:39} ${CON_NAME:0:19} $CPU $CPU2 $MEM $DISK $nas_size $REQCPU $REQMEM "${IMAGESIZE} "


done < $WORK_DIR/conlist.txt

#echo $POD
#kubectl get pod $POD -n $NS -o json | jq ".spec.containers[].resources"
done < $WORK_DIR/list.txt | tee -a $LOGFILE