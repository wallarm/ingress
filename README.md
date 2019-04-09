# NGINX Ingress Controller


## Description

This repository contains the Wallarm-instrumented NGINX controller. Wallarm provides API monitoring and protection from static and dynamic threats by analyzing payloads and meta-data. To fully function, this controller needs to be connected to Wallarm cloud service which requires a separate subscription. Besides Wallarm module, the Ingress controller in this repository is a full clone of a standard NGINX controller built around the [Kubernetes Ingress resource](http://kubernetes.io/docs/user-guide/ingress/) that uses [ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#understanding-configmaps-and-pods) to store the NGINX configuration. Review [Wallarm WAF for Kubernetes](https://wallarm.com/solutions/waf-for-kubernetes/) page to get you started.

### What is an Ingress Controller?

Configuring a webserver or loadbalancer is harder than it should be. Most webserver configuration files are very similar. There are some applications that have weird little quirks that tend to throw a wrench in things, but for the most part you can apply the same logic to them and achieve a desired result.

The Ingress resource embodies this idea, and an Ingress controller is meant to handle all the quirks associated with a specific "class" of Ingress.

An Ingress Controller is a daemon, deployed as a Kubernetes Pod, that watches the apiserver's `/ingresses` endpoint for updates to the [Ingress resource](https://kubernetes.io/docs/concepts/services-networking/ingress/). Its job is to satisfy requests for Ingresses.

## What is WAF?

A web application firewall (or WAF) filters, monitors, and blocks HTTP APIs to and from a web application. Unlike a regular firewall which looks at network traffic within Layer 4 and mostly analyzes the source and the destination of the IP packets, in a WAF is able to filter the content of specific HTTP request in Layer 7. By inspecting the actual content (both payload and meta-data) of an incoming REST, SOAP of XML API request, a WAF could prevent attacks stemming from web application vulnerabilities, such as SQL injection, cross-site scripting (XSS), and security misconfigurations. Many such vulnerabilities are prioritized by OWASP, the Open Web Application Security Project, which periodically publishes OWASP Top 10 list.  Most WAF relly on regular expressions ruleset that use a list of patterns or signatures to apply simple string matching and/or regular expression checks to detect some of the common vulnerabilities types. These thousands of regular expressions, unfortunately, require regular and manual upkeep, both when new expressions need to be added and to weed out the ones that block legitimate traffic. 

## What is Wallarm Automated Cloud WAF?

Unlike legacy WAFs, [Wallarm cloud-based WAF](https://wallarm.com/products/ng-waf/) module is built from the ground up with the express purpose to automatically protect apps and APIs against the most sophisticated types of attacks. Wallarm WAF module doesn’t use signatures, is resistant to bypasses, and protects against 0-day attacks with its AI-based rules. Wallarm AI-engine learns the context of the protected services and creates dynamic security rules that are customized to each of the endpoints. In practical terms, this means that manual signature and rule management is eliminated and the accuracy of the solution is significantly increased with ultra-low rate of false-positives. Wallarm also uses Machine Learning for fast and broad API protocol parsing. Deep HTTPS request inspection allows Wallarm to parse all the nested formats (such as XML -> JSON -> Base64 etc.) and inspect every API field.
Even though Wallarm uses SaaS AI-engine, the decisions about flagging or blocking an individual API request are made locally within the Ingress controller for optimal performance and latency.


## Documentation

To check out [Live Docs](https://docs.wallarm.com/en/admin-en/installation-kubernetes-en.html)
