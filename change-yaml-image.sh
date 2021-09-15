## 기존 이미지 태그에 앞부분을 127.0.0.1:30001으로 변환
## 이미지 태그에 쌍따음표있은 경우 교체##
## ex image: "jimmidyson/configmap-reload:v0.5.0" 
for file in `find ./ -name "*.yaml"`; do sed -i.back "s#image: [\"A-Za-z.]*/\(.*\)\"#image: 127.0.0.1:30001/\\1#g" $file | grep -w image; done

## 이미지 태그에 쌍따음표가 없는 경우 교체 ##
## ex  image: openzipkin/zipkin-slim:2.21.0
for file in `find ./ -name "*.yaml"`; do sed  "s#image: [\"A-Za-z.]*/\(.*\)#image: 127.0.0.1:30001/\\1#g" $file | grep -w image; done 
