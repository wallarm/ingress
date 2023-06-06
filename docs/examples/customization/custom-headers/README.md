# Custom Headers

## Caveats

Changes to the custom header config maps do not force a reload of the ingress-nginx-controllers.

### Workaround

To work around this limitation, perform a rolling restart of the deployment.

## Example

This example demonstrates configuration of the Ingress-Nginx Controller via
a ConfigMap to pass a custom list of headers to the upstream
server.

[custom-headers.yaml](custom-headers.yaml) defines a ConfigMap in the `ingress-nginx` namespace named `custom-headers`, holding several custom X-prefixed HTTP headers.

```console
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/docs/examples/customization/custom-headers/custom-headers.yaml
```

[configmap.yaml](configmap.yaml) defines a ConfigMap in the `ingress-nginx` namespace named `ingress-nginx-controller`. This controls the [global configuration](../../../user-guide/nginx-configuration/configmap.md) of the ingress controller, and already exists in a standard installation. The key `proxy-set-headers` is set to cite the previously-created `ingress-nginx/custom-headers` ConfigMap.

```console
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/docs/examples/customization/custom-headers/configmap.yaml
```

The Ingress-Nginx Controller will read the `ingress-nginx/ingress-nginx-controller` ConfigMap, find the `proxy-set-headers` key, read HTTP headers from the `ingress-nginx/custom-headers` ConfigMap, and include those HTTP headers in all requests flowing from nginx to the backends.


The above example was for passing a custom list of headers to the upstream server.
To pass the custom headers before sending response traffic to the client, use the add-headers key:

```console
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/docs/examples/customization/custom-headers/configmap-client-response.yaml
```

## Test

Check the contents of the ConfigMaps are present in the nginx.conf file using:
`kubectl exec ingress-nginx-controller-873061567-4n3k2 -n ingress-nginx -- cat /etc/nginx/nginx.conf`
