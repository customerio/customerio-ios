SHELL = /bin/sh

# Setup a sample app for you to then compile. 
# 
# How to use: 
# make setup app=CocoaPods-FCM
setup:
	pod install --project-directory=$(app) || true 
	cp "$(app)/BuildEnvironment.sample.swift" "$(app)/BuildEnvironment.swift" || true
	echo "⚠️ Enter the Customer.io workspace settings into $(app)/BuildEnvironment.swift ⚠️"