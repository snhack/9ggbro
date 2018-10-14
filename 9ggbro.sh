#!/bin/bash

#9ggbro
#Backup utilitary
#08/10/2018
#Anthony DOMINGUE & Etienne SELLAN

#config
NginxConfigFilePath="./dev.conf"
useFirewall=false
pathForCertificates="./"
pathForKeys="./"

: ${DIALOG_OK=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_HELP=2}
: ${DIALOG_EXTRA=3}
: ${DIALOG_ITEM_HELP=4}
: ${DIALOG_ESC=255}

menu(){
    cmd=(dialog --backtitle "Nginx configurator" --cancel-label "Exit" --menu "Menu" 10 70 16)
    options=("List" "View and modify Vhost"
        "Write" "Write configuration in config file and reload Nginx"
        "Information" "Various information and admin shell")
    selection=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    status=$?
    case ${status} in
        ${DIALOG_OK})
            case ${selection} in
                List)
                    listMenu
                ;;
                Write)
                    writeConfigFile
                ;;
                Information)
                    #writeConfigFile
                    echo "Info"
                ;;
            esac
        ;;
        ${DIALOG_CANCEL})
            clear
            echo See ya
            sleep 3
        ;;
    esac
}

listMenu(){
    options=()
    
    for index in ${!serversNames[@]};do
        options+=(${serversNames[$index]})
        options+=(${serversSSL[$index]})
    done
    
    cmd=(dialog --backtitle "list" --cancel-label "Back" --menu "list" 15 70 15)
    selection=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
    status=$?
    case ${status} in
        ${DIALOG_OK})
            echo "test"
        ;;
        ${DIALOG_CANCEL})
            echo "test"
        ;;
        ${DIALOG_ESC})
            echo "test"
        ;;
    esac
}

NginxCheckStatus(){
    if [ $(nginx -v >/dev/null 2>&1; echo $?) -ne "0" ]
    then
        echo "Nginx not installed"
    else
        
        echo "Web server installed : Nginx"
        
        echo "$(nginx -v)"
        
        [ $(systemctl status nginx >/dev/null 2>&1; echo $?) -eq "0" ] && NginxStatus="running" || NginxStatus="stopped"
        echo "Nginx status : $NginxStatus"
        
        [ $(nginx -t >/dev/null 2>&1; echo $?) -eq "0" ] && NginxConfigCheck="success" || NginxConfigCheck="fail"
        echo "Nginx config check : $NginxConfigCheck"
    
    fi
}

loadInventory(){
    echo "Loading inventory..."
    
    dataNames=("serversNames" "serversPorts" "serversSSL" "serversCertificate" "serversKey" "serversLocationType" "serversLocationData")
    
    i=-1
    while IFS= read -r line;do
        
        [ $(echo $line | grep "server {" >/dev/null 2>&1; echo $?) -eq "0" ] && ((i++)) && serversSSL[$i]="off"
        
        [ $(echo $line | grep "server_name" >/dev/null 2>&1; echo $?) -eq "0" ] && serversNames[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
        [ $(echo $line | grep "listen" >/dev/null 2>&1; echo $?) -eq "0" ] && serversPorts[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
        [ $(echo $line | grep "ssl on" >/dev/null 2>&1; echo $?) -eq "0" ] && serversSSL[$i]="on"
        [ $(echo $line | grep "ssl_certificate" >/dev/null 2>&1; echo $?) -eq "0" ] && serversCertificate[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
        [ $(echo $line | grep "ssl_certificate_key" >/dev/null 2>&1; echo $?) -eq "0" ] && serversKey[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
        [ $(echo $line | grep "root /" >/dev/null 2>&1; echo $?) -eq "0" ] && serversLocationType[$i]="root" && serversLocationData[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
        [ $(echo $line | grep "proxy_pass" >/dev/null 2>&1; echo $?) -eq "0" ] && serversLocationType[$i]="proxy_pass" && serversLocationData[$i]=$( echo $line | cut -d ' ' -f2 | tr -d ';' )
    
    done < $NginxConfigFilePath
    
    echo "Inventory complete !"
}

addVhost(){
    newID=$(( ${#serversNames[@]} + 1 ))
    serversNames[$newID]=$1
    serversPorts[$newID]=$2
    serversLocationType[$newID]=$3
    serversLocationData[$newID]=$4
    if [ $5 == "on" ]
    then
        serversSSL[$newID]="on"
        if [ -z "$6" ]
        then
            sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $pathForKeys$1.key -out $pathForCertificates$1.crt
            serversCertificate[$newID]="/etc/ssl/certs/$1.crt"
            serversKey[$newID]="/etc/ssl/private/$1.key"
        else
            serversCertificate[$newID]=$6
            serversKey[$newID]=$7
        fi
    else
        serversSSL[$newID]="off"
    fi
}

editProperty(){
    vhostID=$1
    propertyName=$2
    newValue=$3
    
    propertyName=$propertyName[$vhostID]
    
    eval $propertyName=$newValue
}

writeConfigFile(){
    path="./test.conf"
    echo "" > $path
    for index in ${!serversNames[@]};do
        echo "server {" >> $path
        echo "  listen ${serversPorts[$index]};" >> $path
        echo "  server_name ${serversNames[$index]};" >> $path
        echo "  ssl ${serversSSL[$index]};" >> $path
        if [ ${serversSSL[$index]} == "on" ]
        then
            echo "  ssl_certificate ${serversCertificate[$index]};" >> $path
            echo "  ssl_certificate_key ${serversKey[$index]};" >> $path
        fi
        echo "  location / {" >> $path
        echo "      ${serversLocationType[$index]} ${serversLocationData[$index]};" >> $path
        echo "  }" >> $path
        echo "}" >> $path
    done
    
    systemctl reload nginx
    
    if [ $useFirewall == true ]
    then
        setFirewallRules
    fi
}

setFirewallRules(){
    echo "Test"
}

getCertificateExpiration(){
    certificatePath=$1
    return openssl x509 -enddate -noout -in $certificatePath
}

deleteFromInventory(){
    idToRemove=$1
    for property in "${dataNames[@]}"
    do
        property=$property[$idToRemove]
        eval unset $property
    done
}


#execution

loadInventory
menu
#deleteFromInventory 2
#addVhost "test.fr" 80 "proxy_pass" "https://google.fr" "on"
#getCertificateExpiration "./test.fr.crt"
#writeConfigFile

#tmp=${dataNames[5]}
#echo $tmp