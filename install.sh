#!/bin/bash

#====================================================
#	System Request:Debian 7+/Ubuntu 14.04+/Centos 6+
#	Author:	wulabing, jackgan90
#	Dscription: V2ray ws+tls onekey 
#	Version: 3.3.1
#	Blog: https://www.wulabing.com
#	Official document: www.v2ray.com
#====================================================

#fonts color
Green="\033[32m" 
Red="\033[31m" 
Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
Info="${Green}[Info]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[Error]${Font}"

v2ray_conf_dir="/etc/v2ray"
nginx_conf_dir="/etc/nginx/conf.d"
v2ray_conf="${v2ray_conf_dir}/config.json"
nginx_conf="${nginx_conf_dir}/v2ray.conf"

#Generate a random path to be used as websocket path
camouflage=`cat /dev/urandom | head -n 10 | md5sum | head -c 8`

source /etc/os-release

#Extract Linux OS name from VERSION in order to add the corresponding nginx source 
VERSION=`echo ${VERSION} | awk -F "[()]" '{print $2}'`

check_system(){
    
    if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]];then
        echo -e "${OK} ${GreenBG} Current OS: Centos ${VERSION_ID} ${VERSION} ${Font} "
        INS="yum"
        echo -e "${OK} ${GreenBG} Applying SElinux setting, please be patient and dont't take any operation.${Font} "
        setsebool -P httpd_can_network_connect 1
        echo -e "${OK} ${GreenBG} SElinux Applied. ${Font} "
		## It's also OK to add epel repo to install nginx
        cat>/etc/yum.repos.d/nginx.repo<<EOF
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/mainline/centos/7/\$basearch/
gpgcheck=0
enabled=1
EOF
        echo -e "${OK} ${GreenBG} Nginx source installed. ${Font}" 
    elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 8 ]];then
        echo -e "${OK} ${GreenBG} Current OS: Debian ${VERSION_ID} ${VERSION} ${Font} "
        INS="apt"
		## add nginx apt source
        if [ ! -f nginx_signing.key ];then
        echo "deb http://nginx.org/packages/mainline/debian/ ${VERSION} nginx" >> /etc/apt/sources.list
        echo "deb-src http://nginx.org/packages/mainline/debian/ ${VERSION} nginx" >> /etc/apt/sources.list
        wget -nc https://nginx.org/keys/nginx_signing.key
        apt-key add nginx_signing.key
        fi
    elif [[ "${ID}" == "ubuntu" && `echo "${VERSION_ID}" | cut -d '.' -f1` -ge 16 ]];then
        echo -e "${OK} ${GreenBG} Current OS: Ubuntu ${VERSION_ID} ${VERSION_CODENAME} ${Font} "
        INS="apt"
		## add nginx apt source
        if [ ! -f nginx_signing.key ];then
        echo "deb http://nginx.org/packages/mainline/ubuntu/ ${VERSION_CODENAME} nginx" >> /etc/apt/sources.list
        echo "deb-src http://nginx.org/packages/mainline/ubuntu/ ${VERSION_CODENAME} nginx" >> /etc/apt/sources.list
        wget -nc https://nginx.org/keys/nginx_signing.key
        apt-key add nginx_signing.key
        fi
    else
        echo -e "${Error} ${RedBG} Current OS is ${ID} ${VERSION_ID} which is not supported yet，exit installation. ${Font} "
        exit 1
    fi

}
is_root(){
    if [ `id -u` == 0 ]
        then echo -e "${OK} ${GreenBG} Current user is root, start to install ${Font} "
        sleep 3
    else
        echo -e "${Error} ${RedBG} Current user is not root，please switch to root and restart installation. ${Font}" 
        exit 1
    fi
}
judge(){
    if [[ $? -eq 0 ]];then
        echo -e "${OK} ${GreenBG} $1 succeeded.${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} $1 failed.${Font}"
        exit 1
    fi
}
ntpdate_install(){
    if [[ "${ID}" == "centos" ]];then
        ${INS} install ntpdate -y
    else
        ${INS} update
        ${INS} install ntpdate -y
    fi
    judge "Install NTPdate service"
}
time_modify(){

    ntpdate_install

    systemctl stop ntp &>/dev/null

    echo -e "${Info} ${GreenBG} Synchronizing system time. ${Font}"
    ntpdate time.nist.gov

    if [[ $? -eq 0 ]];then 
        echo -e "${OK} ${GreenBG} Time synchronization succeeded. ${Font}"
        echo -e "${OK} ${GreenBG} Current system time: `date -R`( Please notice the timezone difference,the error range should be withing 3 minutes.)${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} Time synchronization failed, please check if the ntpupdate service is working properly. ${Font}"
    fi 
}
dependency_install(){
    ${INS} install wget git lsof -y

    if [[ "${ID}" == "centos" ]];then
       ${INS} -y install crontabs
    else
        ${INS} install cron
    fi
    judge "Install crontab"

    ${INS} install bc -y
    judge "Install bc"

    ${INS} install unzip -y
    judge "Install unzip"
}
port_alterid_set(){
    stty erase '^H' && read -p "Input v2ray listening port:(default:443):" port
    [[ -z ${port} ]] && port="443"
    stty erase '^H' && read -p "Input alterID(default:64):" alterID
    [[ -z ${alterID} ]] && alterID="64"
}
modify_port_UUID(){
    let PORT=$RANDOM+10000
    UUID=$(cat /proc/sys/kernel/random/uuid)
    sed -i "/\"port\"/c  \    \"port\":${PORT}," ${v2ray_conf}
    sed -i "/\"id\"/c \\\t  \"id\":\"${UUID}\"," ${v2ray_conf}
    sed -i "/\"alterId\"/c \\\t  \"alterId\":${alterID}" ${v2ray_conf}
    sed -i "/\"path\"/c \\\t  \"path\":\"\/${camouflage}\/\"" ${v2ray_conf}
}
modify_nginx(){
    ## sed 部分地方 适应新配置修正
    if [[ -f /etc/nginx/nginx.conf.bak ]];then
        cp /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf
    fi
    sed -i "1,/listen/{s/listen 443 ssl;/listen ${port} ssl;/}" ${v2ray_conf}
    sed -i "/server_name/c \\\tserver_name ${domain};" ${nginx_conf}
    sed -i "/location/c \\\tlocation \/${camouflage}\/" ${nginx_conf}
    sed -i "/proxy_pass/c \\\tproxy_pass http://127.0.0.1:${PORT};" ${nginx_conf}
    sed -i "/return/c \\\treturn 301 https://${domain}\$request_uri;" ${nginx_conf}
    sed -i "27i \\\tproxy_intercept_errors on;"  /etc/nginx/nginx.conf
}
web_camouflage(){
	##Cautions : this path is conflict with the default path of LNMP,don't ever try to use this script in an environment with LNMP installed
    rm -rf /home/wwwroot && mkdir -p /home/wwwroot && cd /home/wwwroot
	##This repo can be replaced by any valid nginx website project.Thanks wulabing for sharing the repo.
    git clone https://github.com/wulabing/sCalc.git
    judge "Web camouflage"   
	##For CentOS7 above we must change the context of /home/wwwroot to httpd_sys_content_t for nginx to access it
    if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]];then
		chcon -Rt httpd_sys_content_t /home/wwwroot
		judge "Change /home/wwwroot context"
	fi
}
v2ray_install(){
    if [[ -d /root/v2ray ]];then
        rm -rf /root/v2ray
    fi

    mkdir -p /root/v2ray && cd /root/v2ray
    wget  --no-check-certificate https://install.direct/go.sh

    ## wget http://install.direct/go.sh
    
    if [[ -f go.sh ]];then
        bash go.sh --force
        judge "Install V2ray"
    else
        echo -e "${Error} ${RedBG} Failed to download V2ray, please check the download address. ${Font}"
        exit 4
    fi
}
nginx_install(){
    ${INS} install nginx -y
    if [[ -d /etc/nginx ]];then
        echo -e "${OK} ${GreenBG} nginx installed. ${Font}"
        sleep 2
    else
        echo -e "${Error} ${RedBG} failed to install nginx. ${Font}"
        exit 5
    fi
    if [[ ! -f /etc/nginx/nginx.conf.bak ]];then
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
        echo -e "${OK} ${GreenBG} finished back up nginx configuration file. ${Font}"
        sleep 1
    fi
}
ssl_install(){
    if [[ "${ID}" == "centos" ]];then
        ${INS} install socat nc -y        
    else
        ${INS} install socat netcat -y
    fi
    judge "Install SSL certificate generation script dependency"

    curl  https://get.acme.sh | sh
    judge "Install SSL certificate generation script"

}
domain_check(){
    stty erase '^H' && read -p "Input your domain:(eg:www.google.com):" domain
    domain_ip=`ping ${domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    echo -e "${OK} ${GreenBG} Obtaining public IP address of the host,please wait patiently. ${Font}"
    local_ip=`curl -4 ip.sb`
    echo -e "DNS lookup IP : ${domain_ip}"
    echo -e "Local IP: ${local_ip}"
    sleep 2
    if [[ $(echo ${local_ip}|tr '.' '+'|bc) -eq $(echo ${domain_ip}|tr '.' '+'|bc) ]];then
        echo -e "${OK} ${GreenBG} IP matched. ${Font}"
        sleep 2
    else
        echo -e "${Error} ${RedBG} IP mismatched, continue to install？（y/n）${Font}" && read install
        case $install in
        [yY][eE][sS]|[yY])
            echo -e "${GreenBG} Installation continued. ${Font}" 
            sleep 2
            ;;
        *)
            echo -e "${RedBG} Installation stopped. ${Font}" 
            exit 2
            ;;
        esac
    fi
}

port_exist_check(){
    if [[ 0 -eq `lsof -i:"$1" | wc -l` ]];then
        echo -e "${OK} ${GreenBG} $1 Port OK. ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} Port $1 is in use，Detail: ${Font}"
        lsof -i:"$1"
        echo -e "${OK} ${GreenBG} Try to kill the process which is using the port in 5s.${Font}"
        sleep 5
        lsof -i:"$1" | awk '{print $2}'| grep -v "PID" | xargs kill -9
        echo -e "${OK} ${GreenBG} Process killed.${Font}"
        sleep 1
    fi
}
acme(){
    ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --force
    if [[ $? -eq 0 ]];then
        echo -e "${OK} ${GreenBG} SSL certificate generated.${Font}"
        sleep 2
        ~/.acme.sh/acme.sh --installcert -d ${domain} --fullchainpath /etc/v2ray/v2ray.crt --keypath /etc/v2ray/v2ray.key --ecc
        if [[ $? -eq 0 ]];then
        echo -e "${OK} ${GreenBG} SSL certificate installed.${Font}"
        sleep 2
        fi
    else
        echo -e "${Error} ${RedBG} Failed to generate SSL certificate.${Font}"
        exit 1
    fi
}
v2ray_conf_add(){
    cd /etc/v2ray
    wget https://raw.githubusercontent.com/jackgan90/V2Ray_ws-tls_bash_onekey/master/tls/config.json -O config.json
	judge "Download v2ray config.json"
	modify_port_UUID
	judge "Modify v2ray config"
}
nginx_conf_add(){
    touch ${nginx_conf_dir}/v2ray.conf
    cat>${nginx_conf_dir}/v2ray.conf<<EOF
    server {
        listen 443 ssl;
        ssl on;
        ssl_certificate       /etc/v2ray/v2ray.crt;
        ssl_certificate_key   /etc/v2ray/v2ray.key;
        ssl_protocols         TLSv1 TLSv1.1 TLSv1.2;
        ssl_ciphers           HIGH:!aNULL:!MD5;
        server_name           serveraddr.com;
        index index.html index.htm;
        root  /home/wwwroot/sCalc;
        error_page 400 = /400.html;
        location /ray/ 
        {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        }
}
    server {
        listen 80;
        server_name serveraddr.com;
        return 301 https://use.shadowsocksr.win\$request_uri;
    }
EOF

modify_nginx
judge "Modify nginx config"

}

start_process_systemd(){
	systemctl enable nginx
    systemctl start nginx 
    judge "Nginx start"

	systemctl enable v2ray
    systemctl start v2ray
    judge "V2ray start"
}

acme_cron_update(){
    if [[ "${ID}" == "centos" ]];then
        sed -i "/acme.sh/c 0 0 * * 0 systemctl stop nginx && \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" \
        > /dev/null && systemctl start nginx " /var/spool/cron/root
    else
        sed -i "/acme.sh/c 0 0 * * 0 systemctl stop nginx && \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" \
        > /dev/null && systemctl start nginx " /var/spool/cron/crontabs/root
    fi
    judge "Configure cron scheduled task"
}
show_information(){
    clear

    echo -e "${OK} ${Green} Install v2ray+ws+tls finished."
    echo -e "${Red} V2ray configuration ${Font}"
    echo -e "${Red} IP : ${Font} ${domain} "
    echo -e "${Red} port : ${Font} ${port} "
    echo -e "${Red} UUID : ${Font} ${UUID}"
    echo -e "${Red} alterId : ${Font} ${alterID}"
    echo -e "${Red} network : ${Font} ws "
    echo -e "${Red} camouflage : ${Font} none "
    echo -e "${Red} path : ${Font} /${camouflage}/ "
    echo -e "${Red} streaming security : ${Font} tls "

    

}

main(){
    is_root
    check_system
    time_modify
    dependency_install
    domain_check
    port_alterid_set
    v2ray_install
    port_exist_check 80
    port_exist_check ${port}
    nginx_install
    v2ray_conf_add
    nginx_conf_add
    web_camouflage

    systemctl stop nginx
    systemctl stop v2ray
    
    #Put SSL installation to the end to prevent from generating certificate for multiple times.
    ssl_install
    acme
    
    show_information
    start_process_systemd
    acme_cron_update
}

main
