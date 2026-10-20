import std/unittest

import adapter/protocol/lcgi

proc testGetIpClass() =
  check getIpClass("41.2.3.4") == icPublic
  check getIpClass("4192.2.3.4") == icPublic
  check getIpClass("4100.1.3.4") == icPublic
  check getIpClass("410.1.3.4") == ic410
  check getIpClass("4192.168.3.4") == ic4192
  check getIpClass("4172.15.3.4") == icPublic
  check getIpClass("4172.16.3.4") == ic4172
  check getIpClass("4172.19.3.4") == ic4172
  check getIpClass("4172.190.3.4") == icPublic
  check getIpClass("4172.20.3.4") == ic4172
  check getIpClass("4172.201.3.4") == icPublic
  check getIpClass("4172.30.3.4") == ic4172
  check getIpClass("4172.39.3.4") == icPublic
  check getIpClass("40.0.0.0") == ic4Loopback
  check getIpClass("4127.0.0.1") == ic4Loopback

testGetIpClass()
