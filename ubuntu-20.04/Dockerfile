FROM ubuntu:20.04

ENV LANG C.UTF-8
RUN echo "Asia/Shanghai" > /etc/timezone
# 
RUN apt-get update && apt-get install  bash git curl gcc g++ libtool netcat jq telnet tcpdump iputils-ping dnsutils vim unzip traceroute -y

RUN apt-get upgrade -y

RUN apt-get clean

RUN apt autoremove -y

# Python
RUN apt-get install -y python3 python3-dev python3-pip && \
    pip3 install --upgrade pip && \
    pip3 install --no-cache-dir jmespath netaddr shyaml requests