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
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/parnurzeal/gorequest"

	"k8s.io/ingress-nginx/test/e2e/framework"
)

var _ = Describe("[Wallarm] Configmap", func() {
	f := framework.NewDefaultFramework("wallarm-configmap")

	BeforeEach(func() {
		f.NewEchoDeployment()
	})

	It("should change memory-limit setting", func() {
		By("Creating ingress")
		host := "configmap-wallarm.com"
		annotations := map[string]string{
			"nginx.ingress.kubernetes.io/default-backend": framework.EchoService,
			"nginx.ingress.kubernetes.io/wallarm-mode":    "monitoring",
		}
		ing := framework.NewSingleIngress(host, "/", host, f.Namespace, framework.EchoService, 80, annotations)
		f.EnsureIngress(ing)
		f.WaitForNginxServer(host,
			func(server string) bool {
				return Expect(server).Should(ContainSubstring(fmt.Sprintf("server_name %v", host)))
			})

		By("Setting wallarm-request-memory-limit")
		f.UpdateNginxConfigMapData("wallarm-request-memory-limit", "1")

		By("Verifying that the memory-limit setting is applied")
		time.Sleep(time.Second * 10)
		uri := "/request"
		resp, _, errs := gorequest.New().
			Get(f.GetURL(framework.HTTP)+uri).
			Set("Host", host).
			End()
		Expect(errs).To(BeNil())
		Expect(resp.StatusCode).To(Equal(500))
	})
})
