#!/bin/sh
docker build . -t kali-wctf:0.9
docker tag kali-wctf:latest
docker push kali-wctf rfhs/kali
