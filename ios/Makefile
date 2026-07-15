TARGET = iphone:clang:latest:16.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Walkie
include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Walkie
Walkie_FILES = Walkie/WalkieApp.swift Walkie/ContentView.swift \
	Walkie/Models/Channel.swift Walkie/Models/VoiceMessage.swift \
	Walkie/Services/APIClient.swift Walkie/Services/WebSocketClient.swift \
	Walkie/Services/AudioSessionManager.swift Walkie/Services/DownloadManager.swift \
	Walkie/Services/PersistenceStore.swift Walkie/Services/QRCodeGenerator.swift \
	Walkie/ViewModels/WalkieViewModel.swift
Walkie_FRAMEWORKS = UIKit AVFoundation CoreImage
Walkie_RESOURCE_DIRS = Resources Walkie/Resources
include $(THEOS_MAKE_PATH)/application.mk
