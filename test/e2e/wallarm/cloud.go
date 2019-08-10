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

package wallarm

import (
	"fmt"
	"net/http"
	"strconv"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/parnurzeal/gorequest"
	"k8s.io/ingress-nginx/test/e2e/framework"
)

var _ = Describe("[Wallarm] Cloud", func() {
	f := &framework.Framework{
		BaseName: "wallarm-cloud",
	}

	BeforeEach(func() {
		f.WallarmBeforeEachPart()
		f.NewEchoDeployment()
	})
	AfterEach(f.AfterEach)

	It("should not start pods w/o cloud connectivity", func() {

		By("Starting new ingress controller w/o cloud")
		err := f.WallarmNewProxyIngressController(f.Namespace, f.BaseName, f.Node.Token)
		Expect(err).To(HaveOccurred())

		By("Waiting for ready pod with ingress-controller")
		err = f.WallarmWaitForPodsReady("component=controller", 1)
		Expect(err).To(HaveOccurred())

		By("Waiting for ready pod with tarantool")
		err = f.WallarmWaitForPodsReady("component=controller-wallarm-tarantool", 1)
		Expect(err).To(HaveOccurred())

		By("Checking error message in addnode container for ingress-nginx pod")
		pod, err := f.WallarmSelectPod("component=controller")
		Expect(err).ToNot(HaveOccurred())

		log, err := f.WallarmLogsContainer(pod, "addnode")
		Expect(err).ToNot(HaveOccurred())
		Expect(log).Should(ContainSubstring("Can't create new instance - Failed to open TCP connection"))

		By("Checking error message in addnode container for ingress-nginx-wallarm-tarantool pod")
		pod, err = f.WallarmSelectPod("component=controller-wallarm-tarantool")
		Expect(err).ToNot(HaveOccurred())

		log, err = f.WallarmLogsContainer(pod, "addnode")
		Expect(err).ToNot(HaveOccurred())
		Expect(log).Should(ContainSubstring("Can't create new instance - Failed to open TCP connection"))

		By("Starting api proxy")
		err = f.WallarmEnsureAPIProxy()
		Expect(err).ToNot(HaveOccurred())

		By("Waiting 5 min for restart pods")
		time.Sleep(time.Minute * 5)

		By("Waiting for ready pod with ingress-controller")
		err = f.WallarmWaitForPodsReady("component=controller", 1)
		Expect(err).ToNot(HaveOccurred())

		By("Waiting for ready pod with tarantool")
		err = f.WallarmWaitForPodsReady("component=controller-wallarm-tarantool", 1)
		Expect(err).ToNot(HaveOccurred())

		By("Checking instance count")
		time.Sleep(time.Second * 30)
		err = f.UpdateInfo()
		Expect(err).ToNot(HaveOccurred())
		Expect(f.Node.ActiveInstanceCount).To(Equal(2))
		Expect(f.Node.InstanceCount).To(Equal(2))
	})

	It("should not start pods with invalid token", func() {
		By("Starting new ingress controller with invalid token")
		err := f.WallarmNewIngressController(f.Namespace, f.BaseName, "invalid-token")
		Expect(err).To(HaveOccurred())

		By("Waiting for ready pod with ingress-controller")
		err = f.WallarmWaitForPodsReady("component=controller", 1)
		Expect(err).To(HaveOccurred())

		By("Waiting for ready pod with tarantool")
		err = f.WallarmWaitForPodsReady("component=controller-wallarm-tarantool", 1)
		Expect(err).To(HaveOccurred())

		By("Checking error message in addnode container for ingress-nginx pod")
		pod, err := f.WallarmSelectPod("component=controller")
		Expect(err).ToNot(HaveOccurred())
		log, err := f.WallarmLogsContainer(pod, "addnode")
		Expect(err).ToNot(HaveOccurred())
		Expect(log).Should(ContainSubstring("Can't register node instance: Bad api token"))

		By("Checking error message in addnode container for ingress-nginx-wallarm-tarantool pod")
		pod, err = f.WallarmSelectPod("component=controller-wallarm-tarantool")
		Expect(err).ToNot(HaveOccurred())
		log, err = f.WallarmLogsContainer(pod, "addnode")
		Expect(err).ToNot(HaveOccurred())
		Expect(log).Should(ContainSubstring("Can't register node instance: Bad api token"))

	})

	It("should restore connect to cloud", func() {
		By("Starting api proxy")
		err := f.WallarmEnsureAPIProxy()
		Expect(err).ToNot(HaveOccurred())

		By("Starting new ingress controller")
		err = f.WallarmNewProxyIngressController(f.Namespace, f.BaseName, f.Node.Token)
		Expect(err).ToNot(HaveOccurred())

		By("Wait for ready pod with ingress-controller")
		err = f.WallarmWaitForPodsReady("component=controller", 1)
		Expect(err).ToNot(HaveOccurred())

		By("Wait for ready pod with tarantool")
		err = f.WallarmWaitForPodsReady("component=controller-wallarm-tarantool", 1)
		Expect(err).ToNot(HaveOccurred())

		By("Create application")
		err = f.NewApplication()
		Expect(err).NotTo(HaveOccurred())

		By("Creating ingress")
		host := fmt.Sprintf("break-cloud-%d.wallarm.com", f.WApp.ID)
		annotations := map[string]string{
			"nginx.ingress.kubernetes.io/default-backend":  framework.EchoService,
			"nginx.ingress.kubernetes.io/wallarm-mode":     "block",
			"nginx.ingress.kubernetes.io/wallarm-instance": strconv.Itoa(f.WApp.ID),
		}
		ing := framework.NewSingleIngress(host, "/", host, f.Namespace, framework.EchoService, 80, annotations)
		f.EnsureIngress(ing)
		f.WaitForNginxServer(host,
			func(server string) bool {
				return Expect(server).Should(ContainSubstring(fmt.Sprintf("server_name %v", host)))
			})

		By("Destroing api proxy")
		err = f.WallarmDestroyAPIProxy()
		Expect(err).ToNot(HaveOccurred())
		time.Sleep(time.Second * 30)

		By("Sending attack")
		uri := "/union+select"
		resp, _, errs := gorequest.New().
			Get(f.GetURL(framework.HTTP)+uri).
			Set("Host", host).
			End()
		Expect(errs).Should(BeEmpty())
		Expect(resp.StatusCode).Should(Equal(http.StatusForbidden))

		By("Waiting attack in cloud")
		Consistently(func() error {
			_, err = f.GetAttack()
			return err
		}, "5m", "30s").Should(HaveOccurred())

		By("Checking instance count")
		err = f.UpdateInfo()
		Expect(err).ToNot(HaveOccurred())
		Expect(f.Node.ActiveInstanceCount).To(Equal(0))
		Expect(f.Node.InstanceCount).To(Equal(0))

		By("Starting api proxy")
		err = f.WallarmEnsureAPIProxy()
		Expect(err).ToNot(HaveOccurred())

		By("Waiting attack in cloud")
		attack := &framework.WallarmAttack{}
		Eventually(func() error {
			attack, err = f.GetAttack()
			return err
		}, "20m", "10s").Should(BeNil())
		Expect(attack.Type).Should(Equal("sqli"))

		By("Checking instance count")
		err = f.UpdateInfo()
		Expect(err).ToNot(HaveOccurred())
		Expect(f.Node.ActiveInstanceCount).To(Equal(2))
		Expect(f.Node.InstanceCount).To(Equal(2))
	})
})
