## POD LIST ##
## 러닝 상태만 체크
DATE=`date +%Y/%m/%d:%H:%M`
LOGFILE=log-$(date +%Y%m%d%H%M).txt
WORK_DIR=/root/jungwon

kubectl get pod -A -o wide |grep Running| awk '{printf "%-30s %-40s %-20s\n", $1,$2,$8}' | sort | grep -v NAMESPACE> $WORK_DIR/list.txt 

#echo HEAD
printf "%-20s %-15s %-40s %-20s %-7s %-5s %-10s %-10s %-5s %-10s %-10s \n" "DATE" "NAMESPACE" "POD" "CONNAME" "CPU(m)" "CPU(%)" "MEM" "DISK" "REQCPU" "REQMEM" "IMAGESIZE" > $WORK_DIR/$LOGFILE

while read line
do 
NS=`echo $line| awk '{print $1}'`
POD=`echo $line| awk '{print $2}'`
NODE=`echo $line | awk '{print $3}'`


TEMP=`kubectl top pod $POD -n $NS | grep -v NAME`

CPU2="0"
DISK="0"
CPU=`echo $TEMP | awk '{print $2}'`
MEM=`echo $TEMP | awk '{print $3}'`


#printf "%-30s %-40s %-10s %-10s \n" $NS $POD $CPU $MEM

#container count

kubectl get pod $POD -n $NS -o json | jq -r ".spec.containers[].name" > $WORK_DIR/conlist.txt

while read con
do

REQCPU=`kubectl get pod $POD -n $NS -o json | jq -r --arg con $con '.spec.containers[]|select(.name==$con)|.resources.requests|.cpu//0'`
REQMEM=`kubectl get pod $POD -n $NS -o json | jq -r --arg con $con '.spec.containers[]|select(.name==$con)|.resources.requests|.memory//0'`


IMAGE=`kubectl get pod $POD -n $NS -o json | jq -r --arg con $con '.spec.containers[]|select(.name==$con)|.image'| awk -F: '{if(NF==1) {printf "%s:latest\n",$0}\
 else if(NF==3) {printf "%s:%s\n", $1,$2} \
 else if(NF==2) {split($2,a,"/");if(length(a)>1){printf "%s:latest\n", $0} else {print $0}}}'`

IMAGESIZE=`kubectl get node $NODE -o json | jq -r --arg image $IMAGE '.status.images[]|select(.names[] |contains($image))|.sizeBytes'|uniq `
## 이미지 사이즈가 0이 되는 경우가 있음..노드정보에 이미지 정보가 없음..왜 그러는지 모르겠지만...
if [ "$IMAGESIZE" == "" ];then
IMAGESIZE=0
fi
IMAGESIZE=`echo "scale=2; ${IMAGESIZE}/1024/1024" | bc -l`





#echo  $IMAGE $IMAGESIZE

printf "%-20s %-15s %-40s %-20s %-7s %-5s %-10s %-10s %-5s %-10s %10sMB \n" $DATE ${NS:0:14} ${POD:0:39} ${con:0:19} $CPU $CPU2 $MEM $DISK $REQCPU $REQMEM "${IMAGESIZE}"



done < $WORK_DIR/conlist.txt

#echo $POD
#kubectl get pod $POD -n $NS -o json | jq ".spec.containers[].resources"
done < $WORK_DIR/list.txt  >> $WORK_DIR/$LOGFILE


