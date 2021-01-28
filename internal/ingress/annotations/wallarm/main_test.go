/*
Copyright 2016 The Kubernetes Authors,
          2018 Wallarm Inc.

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
	"testing"

	api "k8s.io/api/core/v1"
	extensions "k8s.io/api/networking/v1beta1"
	meta_v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"

	"k8s.io/ingress-nginx/internal/ingress/annotations/parser"
	"k8s.io/ingress-nginx/internal/ingress/defaults"
	"k8s.io/ingress-nginx/internal/ingress/resolver"
	"reflect"
)

func buildIngress() *extensions.Ingress {
	defaultBackend := extensions.IngressBackend{
		ServiceName: "default-backend",
		ServicePort: intstr.FromInt(80),
	}

	return &extensions.Ingress{
		ObjectMeta: meta_v1.ObjectMeta{
			Name:      "foo",
			Namespace: api.NamespaceDefault,
		},
		Spec: extensions.IngressSpec{
			Backend: &extensions.IngressBackend{
				ServiceName: "default-backend",
				ServicePort: intstr.FromInt(80),
			},
			Rules: []extensions.IngressRule{
				{
					Host: "foo.bar.com",
					IngressRuleValue: extensions.IngressRuleValue{
						HTTP: &extensions.HTTPIngressRuleValue{
							Paths: []extensions.HTTPIngressPath{
								{
									Path:    "/foo",
									Backend: defaultBackend,
								},
							},
						},
					},
				},
			},
		},
	}
}

type mockBackend struct {
	resolver.Mock
}

func (m mockBackend) GetDefaultBackend() defaults.Backend {
	return defaults.Backend{
		WallarmMode: "off",
		WallarmModeAllowOverride: "on",
		WallarmFallback: "on",
		WallarmInstance: "",
		WallarmAcl: "off",
		WallarmBlockPage: "",
		WallarmAclBlockPage: "",
		WallarmParseResponse: "on",
		WallarmParseWebsocket: "off",
		WallarmUnpackResponse: "on",
		WallarmParserDisable: []string{},
	}
}

func TestProxy(t *testing.T) {
	ing := buildIngress()

	data := map[string]string{}
	data[parser.GetAnnotationWithPrefix("wallarm-mode")] = "monitoring"
	data[parser.GetAnnotationWithPrefix("wallarm-mode-allow-override")] = "strict"
	data[parser.GetAnnotationWithPrefix("wallarm-fallback")] = "off"
	data[parser.GetAnnotationWithPrefix("wallarm-instance")] = "42"
	data[parser.GetAnnotationWithPrefix("wallarm-acl")] = "on"
	data[parser.GetAnnotationWithPrefix("wallarm-block-page")] = "block"
	data[parser.GetAnnotationWithPrefix("wallarm-acl-block-page")] = "block"
	data[parser.GetAnnotationWithPrefix("wallarm-parse-response")] = "off"
	data[parser.GetAnnotationWithPrefix("wallarm-parse-websocket")] = "on"
	data[parser.GetAnnotationWithPrefix("wallarm-unpack-response")] = "off"
	data[parser.GetAnnotationWithPrefix("wallarm-parser-disable")] = "xml"
	ing.SetAnnotations(data)

	i, err := NewParser(mockBackend{}).Parse(ing)
	if err != nil {
		t.Fatalf("unexpected error parsing a valid")
	}
	w, ok := i.(*Config)
	if !ok {
		t.Fatalf("expected a Config type")
	}
	if w.Mode != "monitoring" {
		t.Errorf("expected monitoring as wallarm-mode but returned %v", w.Mode)
	}
	if w.ModeAllowOverride != "strict" {
		t.Errorf("expected strict as wallarm-mode-allow-override but returned %v", w.ModeAllowOverride)
	}
	if w.Fallback != "off" {
		t.Errorf("expected off as wallarm-fallback but returned %v", w.Fallback)
	}
	if w.Instance != "42" {
		t.Errorf("expected 42 as wallarm-instance but returned %v", w.Instance)
	}
	if w.Acl != "on" {
		t.Errorf("expected on as wallarm-acl but returned %v", w.Acl)
	}
	if w.BlockPage != "block" {
		t.Errorf("expected block as wallarm-block-page but returned %v", w.BlockPage)
	}
	if w.AclBlockPage != "block" {
		t.Errorf("expected block as wallarm-acl-block-page but returned %v", w.AclBlockPage)
	}
	if w.ParseResponse != "off" {
		t.Errorf("expected off as wallarm-parse-response but returned %v", w.ParseResponse)
	}
	if w.ParseWebsocket != "on" {
		t.Errorf("expected on as wallarm-parse-websocket but returned %v", w.ParseWebsocket)
	}
	if w.UnpackResponse != "off" {
		t.Errorf("expected off as wallarm-unpack-response but returned %v", w.UnpackResponse)
	}
	if !reflect.DeepEqual(w.ParserDisable, []string{"xml"}) {
		t.Errorf("expected xml as wallarm-parser-disable but returned %v", w.ParserDisable)
	}
}

func TestProxyWithNoAnnotation(t *testing.T) {
	ing := buildIngress()

	data := map[string]string{}
	ing.SetAnnotations(data)

	i, err := NewParser(mockBackend{}).Parse(ing)
	if err != nil {
		t.Fatalf("unexpected error parsing a valid")
	}
	p, ok := i.(*Config)
	if !ok {
		t.Fatalf("expected a Config type")
	}
	if p.Mode != "off" {
		t.Errorf(`expected "off" as wallarm-mode but returned %v`, p.Mode)
	}
	if p.ModeAllowOverride != "on" {
		t.Errorf(`expected "on" as wallarm-mode-allow-override but returned %v`, p.ModeAllowOverride)
	}
	if p.Fallback != "on" {
		t.Errorf(`expected "on" as wallarm-fallback but returned %v`, p.Fallback)
	}
	if p.Instance != "" {
		t.Errorf(`expected "" as wallarm-instance but returned %v`, p.Instance)
	}
	if p.Acl != "off" {
		t.Errorf(`expected "off" as wallarm-acl but returned %v`, p.Acl)
	}
	if p.BlockPage != "" {
		t.Errorf(`expected "" as wallarm-block-page but returned %v`, p.BlockPage)
	}
	if p.AclBlockPage != "" {
		t.Errorf(`expected "" as wallarm-acl-block-page but returned %v`, p.AclBlockPage)
	}
	if p.ParseResponse != "on" {
		t.Errorf(`expected "on" as wallarm-parse-response but returned %v`, p.ParseResponse)
	}
	if p.ParseWebsocket != "off" {
		t.Errorf(`expected "off" as wallarm-parse-websocket but returned %v`, p.ParseWebsocket)
	}
	if p.UnpackResponse != "on" {
		t.Errorf(`expected "on" as wallarm-unpack-response but returned %v`, p.UnpackResponse)
	}
	if !reflect.DeepEqual(p.ParserDisable, []string{}) {
		t.Errorf(`expected empty slice as wallarm-parser-disable but returned %v`, p.ParserDisable)
	}
}
