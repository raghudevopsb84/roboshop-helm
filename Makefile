install:
	helm install $(appName) . -f env-dev/$(appName).yaml

