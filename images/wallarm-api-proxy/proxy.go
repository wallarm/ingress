/*
Copyright 2019 Wallarm Inc

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strconv"
)

var apiURL *url.URL

func main() {

	useSSL, err := strconv.ParseBool(os.Getenv("WALLARM_API_USE_SSL"))
	if err != nil {
		panic(err)
	}

	if useSSL {
		apiURL, err = url.Parse(fmt.Sprintf("https://%s:%s", os.Getenv("WALLARM_API_HOST"), os.Getenv("WALLARM_API_PORT")))
	} else {
		apiURL, err = url.Parse(fmt.Sprintf("http://%s:%s", os.Getenv("WALLARM_API_HOST"), os.Getenv("WALLARM_API_PORT")))
	}
	if err != nil {
		panic(err)
	}

	apiProxy := httputil.NewSingleHostReverseProxy(apiURL)
	certs, err := ioutil.ReadFile("ca.pem")
	if err == nil {
		rootCAs := x509.NewCertPool()
		rootCAs.AppendCertsFromPEM(certs)

		config := &tls.Config{
			RootCAs: rootCAs,
		}
		apiProxy.Transport = &http.Transport{TLSClientConfig: config}
	}
	http.HandleFunc("/", proxyHandler(apiProxy))

	srv := &http.Server{Addr: ":8080"}
	srv.ListenAndServe()
}

func proxyHandler(p *httputil.ReverseProxy) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		r.Host = apiURL.Host
		p.ServeHTTP(w, r)
	}
}
