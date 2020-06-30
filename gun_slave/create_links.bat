@echo off
setlocal

cd client 
mklink /D common ..\common 
cd ..
cd server 
mklink /D common ..\common 
cd ..
cd dummy_controller
mklink /D common ..\common 
cd ..
