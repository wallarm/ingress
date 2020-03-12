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

package framework

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"math"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	core "k8s.io/api/core/v1"
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	restclient "k8s.io/client-go/rest"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

// WallarmFramework support wallarm methods for e2e tests
type WallarmFramework struct {
	WAPI *WallarmAPI
	Node *WallarmCloudNode
	WApp *WallarmApplication
}

// WallarmAPI defines credentials for make request to wallarm cloud
type WallarmAPI struct {
	uuid       string
	secret     string
	host       string
	port       string
	useSSL     bool
	httpClient *http.Client
	clientID   int
}

// WallarmCloudNode defines info about node
type WallarmCloudNode struct {
	Name                string `json:"hostname"`
	Token               string `json:"token"`
	InstanceCount       int    `json:"instance_count"`
	ActiveInstanceCount int    `json:"active_instance_count"`
	ID                  int    `json:"id"`
}

// WallarmApplication defines pool id
type WallarmApplication struct {
	ID int
}

// WallarmAttack defines single attack
type WallarmAttack struct {
	Domain      string `json:"domain"`
	Path        string `json:"path"`
	Type        string `json:"Type"`
	StatusCodes []int  `json:"statuscodes"`
}

// NewWallarmAPI gets credentials and uses it to get client id
func (f *WallarmFramework) NewWallarmAPI() (err error) {
	useSSL, err := strconv.ParseBool(os.Getenv("WALLARM_API_USE_SSL"))
	if err != nil {
		return err
	}

	f.WAPI = &WallarmAPI{
		uuid:       os.Getenv("WALLARM_API_UUID"),
		secret:     os.Getenv("WALLARM_API_SECRET"),
		host:       os.Getenv("WALLARM_API_HOST"),
		port:       os.Getenv("WALLARM_API_PORT"),
		useSSL:     useSSL,
		httpClient: &http.Client{},
	}

	certs, err := ioutil.ReadFile("ca.pem")
	if f.WAPI.useSSL && err == nil {
		rootCAs := x509.NewCertPool()
		rootCAs.AppendCertsFromPEM(certs)

		config := &tls.Config{
			RootCAs: rootCAs,
		}
		f.WAPI.httpClient.Transport = &http.Transport{TLSClientConfig: config}
	}

	resp, err := f.newRequest("POST", "/v1/user", nil)
	if err != nil {
		return err
	}

	bodyBytes, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("cannot get user: %v: %v", resp.Status, string(bodyBytes))
	}

	var userResp struct {
		Body struct {
			ClientID int `json:"clientid"`
		}
	}
	err = json.Unmarshal(bodyBytes, &userResp)
	if err != nil {
		return err
	}

	f.WAPI.clientID = userResp.Body.ClientID
	return nil
}

func (f *WallarmFramework) newRequest(method, apiQuery string, body io.Reader) (resp *http.Response, err error) {
	var scheme string
	if f.WAPI.useSSL {
		scheme = "https://"
	} else {
		scheme = "http://"
	}

	req, err := http.NewRequest(method, fmt.Sprintf("%s%s:%s%s", scheme, f.WAPI.host, f.WAPI.port, apiQuery), body)
	if err != nil {
		return nil, fmt.Errorf("cannot create request: %v", req.URL)
	}
	req.Header.Set("X-WallarmAPI-UUID", f.WAPI.uuid)
	req.Header.Set("X-WallarmAPI-Secret", f.WAPI.secret)
	if method == "POST" && body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err = f.WAPI.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("cannot process request: %v", req.URL)
	}

	return resp, nil
}

// NewCloudNode creates new node
func (f *WallarmFramework) NewCloudNode(baseName string) (err error) {
	reqBody := fmt.Sprintf("{\"hostname\":\"%s\",\"type\":\"cloud_node\",\"clientid\":%d}", baseName, f.WAPI.clientID)
	resp, err := f.newRequest("POST", "/v2/node", strings.NewReader(reqBody))
	if err != nil {
		return err
	}

	bodyBytes, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("cannot create node: %v: %v", resp.Status, string(bodyBytes))
	}

	var userResp struct {
		Body *WallarmCloudNode
	}

	err = json.Unmarshal(bodyBytes, &userResp)
	if err != nil {
		return err
	}
	f.Node = userResp.Body
	return nil
}

// UpdateInfo pulls count instances from cloud
func (f *WallarmFramework) UpdateInfo() (err error) {
	resp, err := f.newRequest("GET", fmt.Sprintf("/v2/node?filter[clientid][]=%d&filter[id]=%d", f.WAPI.clientID, f.Node.ID), nil)
	if err != nil {
		return err
	}

	bodyBytes, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("cannot update info: %v: %v", resp.Status, string(bodyBytes))
	}

	var userResp struct {
		Body []*WallarmCloudNode
	}
	err = json.Unmarshal(bodyBytes, &userResp)
	if err != nil {
		return err
	}

	f.Node.InstanceCount = userResp.Body[0].InstanceCount
	f.Node.ActiveInstanceCount = userResp.Body[0].ActiveInstanceCount
	return nil
}

// DestroyNode delete node from cloud
func (f *WallarmFramework) DestroyNode() (err error) {
	resp, err := f.newRequest("DELETE", fmt.Sprintf("/v2/node/%d", f.Node.ID), nil)
	if err != nil {
		return err
	}

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("cannot delete node %v: %v: %v", f.Node.ID, resp.Status, string(bodyBytes))
	}
	return nil
}

// NewApplication register new pool in cloud
func (f *WallarmFramework) NewApplication() (err error) {
	f.WApp = &WallarmApplication{
		ID: int(time.Now().UnixNano()) % math.MaxInt32,
	}

	reqBody := fmt.Sprintf("{\"id\":%d,\"name\":\"e2e-tests-%d\",\"clientid\": %d}",
		f.WApp.ID, f.WApp.ID, f.WAPI.clientID)
	resp, err := f.newRequest("POST", "/v1/objects/pool/create", strings.NewReader(reqBody))
	if err != nil {
		return err
	}

	bodyBytes, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("cannot create application: %v: %v", resp.Status, string(bodyBytes))
	}

	return nil
}

// DestroyApp deletes application record in cloud
func (f *WallarmFramework) DestroyApp() (err error) {
	reqBody := fmt.Sprintf("{\"filter\": {\"id\":%d,\"clientid\":%d}}", f.WApp.ID, f.WAPI.clientID)
	resp, err := f.newRequest("POST", "/v1/objects/pool/delete", strings.NewReader(reqBody))
	if err != nil {
		return err
	}

	if resp.StatusCode != http.StatusOK {
		bodyBytes, _ := ioutil.ReadAll(resp.Body)
		return fmt.Errorf("cannot delete application %v: %v: %v", f.WApp.ID, resp.Status, string(bodyBytes))
	}
	return nil
}

// GetAttack pulls last attack from cloud
func (f *WallarmFramework) GetAttack() (attack *WallarmAttack, err error) {
	attack = &WallarmAttack{}

	// Search in last 20 minutes
	startPeriod := time.Now().Unix() - 1200
	endPeriod := time.Now().Unix()

	reqBody := fmt.Sprintf("{\"filter\": {\"clientid\": [%d], \"poolid\": [%d], \"time\": [[%d, %d]]}}",
		f.WAPI.clientID, f.WApp.ID, startPeriod, endPeriod)

	resp, err := f.newRequest("POST", "/v1/objects/attack", strings.NewReader(reqBody))
	if err != nil {
		return nil, err
	}

	bodyBytes, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("cannot get attack: %v: %v", resp.Status, string(bodyBytes))
	}

	var userResp struct {
		Body []WallarmAttack
	}
	err = json.Unmarshal(bodyBytes, &userResp)
	if err != nil {
		return nil, err
	}

	attacks := userResp.Body
	if len(attacks) == 1 {
		fmt.Println(attacks[0])
		return &attacks[0], nil
	}
	return nil, fmt.Errorf("got %d attacks instead one", len(attacks))
}

// WallarmBeforeEachPart gets a client and makes a namespace.
func (f *Framework) WallarmBeforeEachPart() {
	f.cleanupHandle = AddCleanupAction(f.AfterEach)

	By("Creating a kubernetes client")
	kubeConfig, err := restclient.InClusterConfig()
	if err != nil {
		panic(err.Error())
	}

	Expect(err).NotTo(HaveOccurred())

	f.KubeConfig = kubeConfig
	f.KubeClientSet, err = kubernetes.NewForConfig(kubeConfig)
	Expect(err).NotTo(HaveOccurred())

	By("Building a namespace api object")
	ingressNamespace, err := CreateKubeNamespace(f.BaseName, f.KubeClientSet)
	Expect(err).NotTo(HaveOccurred())

	f.Namespace = ingressNamespace

	By("Creating new Wallarm API")
	err = f.NewWallarmAPI()
	Expect(err).NotTo(HaveOccurred())

	By("Creating new Wallarm Node")
	err = f.NewCloudNode(f.Namespace)
	Expect(err).NotTo(HaveOccurred())

}

// WallarmWaitForPodsReady waits for ready pods or return error by timeout
func (f *Framework) WallarmWaitForPodsReady(selector string, expectedReplicas int) error {
	err := WaitForPodsReady(f.KubeClientSet, DefaultTimeout, expectedReplicas, f.Namespace, metav1.ListOptions{
		LabelSelector: selector,
	})
	return err
}

// WallarmSelectPod gets pod by selector
func (f *Framework) WallarmSelectPod(selector string) (*core.Pod, error) {
	l, _ := f.KubeClientSet.CoreV1().Pods(f.Namespace).List(metav1.ListOptions{
		LabelSelector: selector,
	})

	if len(l.Items) == 0 {
		return nil, fmt.Errorf("Can't find pod by selector")
	}

	if len(l.Items) > 1 {
		return nil, fmt.Errorf("Finded more that one pod")
	}

	return &l.Items[0], nil
}

// WallarmLogsContainer returns logs for container
func (f *Framework) WallarmLogsContainer(pod *v1.Pod, containerName string) (string, error) {
	var (
		execOut bytes.Buffer
		execErr bytes.Buffer
	)

	cmd := exec.Command("/bin/bash", "-c", fmt.Sprintf("%v logs --namespace %s %s -c %s", KubectlPath, pod.Namespace, pod.Name, containerName))

	cmd.Stdout = &execOut
	cmd.Stderr = &execErr

	err := cmd.Run()
	if err != nil {
		return "", fmt.Errorf("could not execute '%s %s': %v", cmd.Path, cmd.Args, err)
	}

	if execErr.Len() > 0 {
		return "", fmt.Errorf("stderr: %v", execErr.String())
	}

	return execOut.String(), nil
}

// WallarmNewIngressController deploys a new NGINX Ingress controller with Wallarm in a namespace
func (f *Framework) WallarmNewIngressController(namespace string, namespaceOverlay string, token string) error {
	// Creates an nginx deployment
	cmd := exec.Command("./wait-for-nginx.sh", namespace, namespaceOverlay)
	cmd.Env = append(os.Environ(),
		fmt.Sprintf("WALLARM_API_TOKEN=%s", token),
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("Unexpected error waiting for wallarm-ingress controller deployment: %v.\nLogs:\n%v", err, string(out))
	}

	return nil
}

// WallarmNewProxyIngressController deploys a new NGINX Ingress controller with Wallarm  and configure through api-proxy
func (f *Framework) WallarmNewProxyIngressController(namespace string, namespaceOverlay string, token string) error {
	// Creates an nginx deployment
	cmd := exec.Command("./wait-for-nginx.sh", namespace, namespaceOverlay)
	cmd.Env = append(os.Environ(),
		fmt.Sprintf("WALLARM_API_TOKEN=%s", token),
		"WALLARM_API_HOST=wallarm-api-proxy",
		"WALLARM_API_PORT=8080",
		"WALLARM_API_USE_SSL=false",
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("Unexpected error waiting for wallarm-proxy-ingress controller deployment: %v.\nLogs:\n%v", err, string(out))
	}

	return nil
}

// WallarmEnsureAPIProxy deploys api-proxy
func (f *Framework) WallarmEnsureAPIProxy() error {
	var (
		execOut bytes.Buffer
		execErr bytes.Buffer
	)

	sed := `sed "s@\${REGISTRY}@${REGISTRY}@" manifests/wallarm-api-proxy.yaml | \
	sed --expression="s@\${TAG}@${TAG}@" | \
	sed --expression="s@\${WALLARM_API_HOST}@${WALLARM_API_HOST}@" | \
	sed --expression="s@\${WALLARM_API_PORT}@${WALLARM_API_PORT}@" | \
	sed --expression="s@\${WALLARM_API_USE_SSL}@${WALLARM_API_USE_SSL}@"`

	cmd := exec.Command("/bin/bash", "-c", fmt.Sprintf("%s | %v apply --namespace=%s -f -", sed, KubectlPath, f.Namespace))
	cmd.Stdout = &execOut
	cmd.Stderr = &execErr

	err := cmd.Run()
	if err != nil {
		return fmt.Errorf("could not create wallarm api proxy: exit status: %v: stderr %v", err, execErr.String())

	}

	time.Sleep(time.Second * 5)

	return nil
}

// WallarmDestroyAPIProxy deletes api-proxy
func (f *Framework) WallarmDestroyAPIProxy() error {
	var (
		execOut bytes.Buffer
		execErr bytes.Buffer
	)

	cmd := exec.Command("/bin/bash", "-c", fmt.Sprintf("%v delete --namespace=%s -f manifests/wallarm-api-proxy.yaml", KubectlPath, f.Namespace))
	cmd.Stdout = &execOut
	cmd.Stderr = &execErr

	err := cmd.Run()
	if err != nil {
		return fmt.Errorf("could not destroy wallarm api proxy: exit status: %v: stderr %v", err, execErr.String())

	}

	time.Sleep(time.Second * 5)

	return nil
}
