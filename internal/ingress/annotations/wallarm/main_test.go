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

//nolint:gofumpt,goconst // maybe later
package wallarm

import (
	"testing"

	api "k8s.io/api/core/v1"
	networking "k8s.io/api/networking/v1"
	meta_v1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"reflect"

	"k8s.io/ingress-nginx/internal/ingress/annotations/parser"
	"k8s.io/ingress-nginx/internal/ingress/defaults"
	"k8s.io/ingress-nginx/internal/ingress/resolver"
)

func buildIngress() *networking.Ingress {
	defaultBackend := networking.IngressBackend{
		Service: &networking.IngressServiceBackend{
			Name: "default-backend",
			Port: networking.ServiceBackendPort{
				Number: 80,
			},
		},
	}

	return &networking.Ingress{
		ObjectMeta: meta_v1.ObjectMeta{
			Name:      "foo",
			Namespace: api.NamespaceDefault,
		},
		Spec: networking.IngressSpec{
			DefaultBackend: &networking.IngressBackend{
				Service: &networking.IngressServiceBackend{
					Name: "default-backend",
					Port: networking.ServiceBackendPort{
						Number: 80,
					},
				},
			},
			Rules: []networking.IngressRule{
				{
					Host: "foo.bar.com",
					IngressRuleValue: networking.IngressRuleValue{
						HTTP: &networking.HTTPIngressRuleValue{
							Paths: []networking.HTTPIngressPath{
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
		WallarmMode:              "off",
		WallarmModeAllowOverride: "on",
		WallarmFallback:          "on",
		WallarmInstance:          "",
		WallarmBlockPage:         "",
		WallarmACLBlockPage:      "",
		WallarmParseResponse:     "on",
		WallarmParseWebsocket:    "off",
		WallarmUnpackResponse:    "on",
		WallarmParserDisable:     []string{},
		WallarmPartnerClientUUID: "",
	}
}

func TestProxy(t *testing.T) {
	ing := buildIngress()

	data := map[string]string{}
	data[parser.GetAnnotationWithPrefix("wallarm-mode")] = "monitoring"
	data[parser.GetAnnotationWithPrefix("wallarm-mode-allow-override")] = "strict"
	data[parser.GetAnnotationWithPrefix("wallarm-fallback")] = "off"
	data[parser.GetAnnotationWithPrefix("wallarm-instance")] = "42"
	data[parser.GetAnnotationWithPrefix("wallarm-partner-client-uuid")] = "11111111-1111-1111-1111-111111111111"
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
	if w.PartnerClientUUID != "11111111-1111-1111-1111-111111111111" {
		t.Errorf("expected 11111111-1111-1111-1111-111111111111 as wallarm-partner-client-uuid but returned %v", w.PartnerClientUUID)
	}
	if w.BlockPage != "block" {
		t.Errorf("expected block as wallarm-block-page but returned %v", w.BlockPage)
	}
	if w.ACLBlockPage != "block" {
		t.Errorf("expected block as wallarm-acl-block-page but returned %v", w.ACLBlockPage)
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
	if p.PartnerClientUUID != "" {
		t.Errorf(`expected "" as wallarm-partner-client-uuid but returned %v`, p.PartnerClientUUID)
	}
	if p.BlockPage != "" {
		t.Errorf(`expected "" as wallarm-block-page but returned %v`, p.BlockPage)
	}
	if p.ACLBlockPage != "" {
		t.Errorf(`expected "" as wallarm-acl-block-page but returned %v`, p.ACLBlockPage)
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

func TestBlockPageValidation(t *testing.T) {
	testcases := []struct {
		configValue string
		valid       bool
	}{
		{"", true},

		{"&/<PATH_TO_FILE/HTML_HTM_FILE_NAME", true},
		{"/url", true},
		{"@namedLocation", true},
		{"&variable", true},
		{"hello/world.html", false},

		{"/url response_code=420", true},
		{"/url response_code=forbidden", false},
		{"/url response-code=420", false},
		{"/url response_code 420", false},

		{"/url type=attack", true},
		{"/url type=attack,acl_ip", true},
		{"/url type=acl_source,attack,acl_ip", true},
		{"/url type=attack acl_ip", false},
		{"/url type=attack,acl", false},
		{"/url type attack,acl_ip", false},

		{"/url type=acl_source,attack,acl_ip response_code=420", true},
		{"/url type=acl_source,attack,acl_ip response_code=420;@namedLocation", true},

		{"/url type=acl_source,attack,acl_ip response_code=420,@namedLocation", false},
		{"/url type=acl_source,attack,acl_ip response_code=420 @namedLocation", false},
	}

	for _, tc := range testcases {
		valid := validateBlockPage(tc.configValue) == nil
		if valid != tc.valid {
			t.Errorf("failed to validate \"%s\", should be %t", tc.configValue, tc.valid)
		}
	}
}
