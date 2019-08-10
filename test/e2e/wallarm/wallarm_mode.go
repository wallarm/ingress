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

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/parnurzeal/gorequest"

	"k8s.io/ingress-nginx/test/e2e/framework"
)

var _ = Describe("[Wallarm] Mode", func() {
	f := framework.NewDefaultFramework("wallarm-mode")

	BeforeEach(func() {
		f.NewEchoDeployment()
	})

	It("should block attacks in blocking mode", func() {
		By("creating ingress in blocking mode")
		host := "block.wallarm.com"
		annotations := map[string]string{
			"nginx.ingress.kubernetes.io/default-backend": framework.EchoService,
			"nginx.ingress.kubernetes.io/wallarm-mode":    "block",
		}
		ing := framework.NewSingleIngress(host, "/", host, f.Namespace, framework.EchoService, 80, annotations)
		f.EnsureIngress(ing)
		f.WaitForNginxServer(host,
			func(server string) bool {
				return Expect(server).Should(ContainSubstring(fmt.Sprintf("server_name %v", host)))
			})

		By("Sending attack in block mode")
		uri := "/union+select"
		resp, _, errs := gorequest.New().
			Get(f.GetURL(framework.HTTP)+uri).
			Set("Host", host).
			End()
		Expect(errs).Should(BeEmpty())
		Expect(resp.StatusCode).Should(Equal(http.StatusForbidden))
	})

	It("should not block attacks in monitoring mode", func() {
		By("creating ingress in monitoring mode")
		host := "monitoring.wallarm.com"
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

		By("Sending attack in monitoring mode")
		uri := "/union+select"
		resp, _, errs := gorequest.New().
			Get(f.GetURL(framework.HTTP)+uri).
			Set("Host", host).
			End()
		Expect(errs).Should(BeEmpty())
		Expect(resp.StatusCode).Should(Equal(http.StatusOK))
	})
})
