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
	extensions "k8s.io/api/networking/v1beta1"

	"k8s.io/ingress-nginx/internal/ingress/annotations/parser"
	"k8s.io/ingress-nginx/internal/ingress/resolver"
	"reflect"
	"strings"
)

type Config struct {
	Mode string `json:"mode"`
	ModeAllowOverride string `json:"modeAllowOverride"`
	Fallback string `json:"fallback"`
	Instance string `json:"instance"`
	BlockPage string `json:"blockPage"`
	AclBlockPage string `json:"aclBlockPage"`
	ParseResponse string `json:"parseResponse"`
	ParseWebsocket string `json:"parseWebsocket"`
	UnpackResponse string `json:"unpackResponse"`
	ParserDisable []string `json:"parserDisable"`
}

// Equal tests for equality between two Configuration types
func (l1 *Config) Equal(l2 *Config) bool {
	if l1 == l2 {
		return true
	}
	if l1 == nil || l2 == nil {
		return false
	}
	if l1.Mode != l2.Mode {
		return false
	}
	if l1.ModeAllowOverride != l2.ModeAllowOverride {
		return false
	}
	if l1.Fallback != l2.Fallback {
		return false
	}
	if l1.Instance != l2.Instance {
		return false
	}
	if l1.BlockPage != l2.BlockPage {
		return false
	}
	if l1.ParseResponse != l2.ParseResponse {
		return false
	}
	if l1.ParseWebsocket != l2.ParseWebsocket {
		return false
	}
	if l1.UnpackResponse != l2.UnpackResponse {
		return false
	}
	if !reflect.DeepEqual(l1.ParserDisable, l2.ParserDisable) {
		return false
	}
	if l1.AclBlockPage != l2.AclBlockPage {
		return false
	}

	return true
}

type wallarm struct {
	r resolver.Resolver
}

// NewParser creates a new wallarm module configuration annotation parser
func NewParser(r resolver.Resolver) parser.IngressAnnotation {
	return wallarm{r}
}

// ParseAnnotations parses the annotations contained in the ingress
// rule used to configure upstream check parameters
func (a wallarm) Parse(ing *extensions.Ingress) (interface{}, error) {

	defBackend := a.r.GetDefaultBackend()
	mode, err := parser.GetStringAnnotation("wallarm-mode", ing)
	if err != nil {
		mode = defBackend.WallarmMode
	}
	modeAllowOverride, err := parser.GetStringAnnotation("wallarm-mode-allow-override", ing)
	if err != nil {
		modeAllowOverride = defBackend.WallarmModeAllowOverride
	}
	fallback, err := parser.GetStringAnnotation("wallarm-fallback", ing)
	if err != nil {
		fallback = defBackend.WallarmFallback
	}
	instance, err := parser.GetStringAnnotation("wallarm-instance", ing)
	if err != nil {
		instance = defBackend.WallarmInstance
	}
	blockPage, err := parser.GetStringAnnotation("wallarm-block-page", ing)
	if err != nil {
		blockPage = defBackend.WallarmBlockPage
	}
	aclBlockPage, err := parser.GetStringAnnotation("wallarm-acl-block-page", ing)
	if err != nil {
		aclBlockPage = defBackend.WallarmAclBlockPage
	}
	parseResponse, err := parser.GetStringAnnotation("wallarm-parse-response", ing)
	if err != nil {
		parseResponse = defBackend.WallarmParseResponse
	}
	parseWebsocket, err := parser.GetStringAnnotation("wallarm-parse-websocket", ing)
	if err != nil {
		parseWebsocket = defBackend.WallarmParseWebsocket
	}
	unpackResponse, err := parser.GetStringAnnotation("wallarm-unpack-response", ing)
	if err != nil {
		unpackResponse = defBackend.WallarmUnpackResponse
	}
	parserDisable := []string{}
	pd, err := parser.GetStringAnnotation("wallarm-parser-disable", ing)
	if err != nil {
		parserDisable = defBackend.WallarmParserDisable
	} else {
		parserDisable = strings.Split(pd, ",")
	}
	for i, v := range parserDisable {
		parserDisable[i] = strings.TrimSpace(v)
	}

	return &Config{
		mode,
		modeAllowOverride,
		fallback,
		instance,
		blockPage,
		aclBlockPage,
		parseResponse,
		parseWebsocket,
		unpackResponse,
		parserDisable,
	}, nil
}
