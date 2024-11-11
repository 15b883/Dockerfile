FROM ubuntu:20.04

ENV LANG C.UTF-8

RUN echo "Asia/Shanghai" > /etc/timezone
# 
RUN apt-get update 

RUN apt-get install  bash git curl netcat jq telnet tcpdump iputils-ping dnsutils vim unzip traceroute -y

RUN apt-get upgrade -y

RUN apt-get clean

RUN apt autoremove -y
