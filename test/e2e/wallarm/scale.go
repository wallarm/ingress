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
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"

	"k8s.io/ingress-nginx/test/e2e/framework"
)

var _ = Describe("[Wallarm] Scale", func() {
	f := framework.NewDefaultFramework("wallarm-scale")

	BeforeEach(func() {
		f.NewEchoDeployment()
	})

	It("should tarantool scale up and down", func() {

		By("Checking setup")
		err := f.UpdateInfo()
		Expect(err).ToNot(HaveOccurred())
		Expect(f.Node.ActiveInstanceCount).To(Equal(2))
		Expect(f.Node.InstanceCount).To(Equal(2))

		By("Scaling tarantool up")
		replicas := 2
		err = framework.UpdateDeployment(f.KubeClientSet, f.Namespace, "nginx-ingress-controller-wallarm-tarantool", replicas, nil)
		Expect(err).NotTo(HaveOccurred())

		err = f.WallarmWaitForPodsReady("component=controller-wallarm-tarantool", replicas)
		Expect(err).ToNot(HaveOccurred())

		err = f.UpdateInfo()
		Expect(err).ToNot(HaveOccurred())
		Expect(f.Node.ActiveInstanceCount).To(Equal(3))
		Expect(f.Node.InstanceCount).To(Equal(3))

		By("Scaling tarantool down")
		replicas = 1
		err = framework.UpdateDeployment(f.KubeClientSet, f.Namespace, "nginx-ingress-controller-wallarm-tarantool", replicas, nil)
		Expect(err).NotTo(HaveOccurred())

		err = f.WallarmWaitForPodsReady("component=controller-wallarm-tarantool", replicas)
		Expect(err).ToNot(HaveOccurred())

		time.Sleep(time.Minute * 2)
		err = f.UpdateInfo()
		Expect(err).ToNot(HaveOccurred())
		Expect(f.Node.ActiveInstanceCount).To(Equal(2))
		Expect(f.Node.InstanceCount).To(Equal(3))

	})
})
