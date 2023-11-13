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
	"fmt"
	"reflect"
	"regexp"
	"strconv"
	"strings"

	networking "k8s.io/api/networking/v1"
	"k8s.io/ingress-nginx/internal/ingress/annotations/parser"
	"k8s.io/ingress-nginx/internal/ingress/resolver"
)

const (
	wallarmModeAnnotation              = "wallarm-mode"
	wallarmModeAllowOverrideAnnotation = "wallarm-mode-allow-override"
	wallarmFallbackAnnotation          = "wallarm-fallback"
	wallarmApplicationAnnotation       = "wallarm-application"
	wallarmInstanceAnnotation          = "wallarm-instance" // alias for wallarmApplicationAnnotation
	wallarmPartnerClientUUIDAnnotation = "wallarm-partner-client-uuid"
	wallarmBlockPageAnnotation         = "wallarm-block-page"
	wallarmACLBlockPageAnnotation      = "wallarm-acl-block-page"
	wallarmParseResponseAnnotation     = "wallarm-parse-response"
	wallarmParseWebsocketAnnotation    = "wallarm-parse-websocket"
	wallarmUnpackResponseAnnotation    = "wallarm-unpack-response"
	wallarmParserDisableAnnotation     = "wallarm-parser-disable"
)

func validateApplicationID(s string) error {
	i, err := strconv.Atoi(s)
	if err == nil && i <= 0 {
		err = fmt.Errorf("value should be positive integer")
	}
	return err
}

func validateParserDisable(s string) error {
	allowedParsers := map[string]bool{
		"cookie":    true,
		"zlib":      true,
		"htmljs":    true,
		"json":      true,
		"multipart": true,
		"base64":    true,
		"percent":   true,
		"urlenc":    true,
		"xml":       true,
		"jwt":       true,
	}
	for _, value := range strings.Split(s, ",") {
		parserName := strings.TrimSpace(value)
		if _, ok := allowedParsers[value]; !ok {
			return fmt.Errorf("unknown parser \"%s\"", parserName)
		}
	}
	return nil
}

// https://docs.wallarm.com/admin-en/configuration-guides/configure-block-page-and-code/
func validateBlockPage(s string) error {
	if s == "" {
		return nil
	}
	for _, value := range strings.Split(s, ";") {
		valueSplit := strings.Split(value, " ")
		page := valueSplit[0]
		switch page[0] {
		case '/', '&', '@', '$':
			break
		default:
			return fmt.Errorf("invalid block page format \"%s\"", page)
		}
		if len(valueSplit) == 1 {
			continue
		}
		for _, optional := range valueSplit[1:] {
			optionalSplit := strings.Split(optional, "=")
			if len(optionalSplit) != 2 {
				return fmt.Errorf("invalid block page optional param format \"%s\"", optional)
			}
			optionalKey := optionalSplit[0]
			optionalValue := optionalSplit[1]
			switch optionalKey {
			case "response_code":
				_, err := strconv.Atoi(optionalValue)
				if err != nil {
					return fmt.Errorf("invalid response_code value \"%s\"", optionalValue)
				}
			case "type":
				for _, typeValue := range strings.Split(optionalValue, ",") {
					switch typeValue {
					case "acl_ip", "acl_source", "attack":
						break
					default:
						return fmt.Errorf("invalid type value \"%s\"", typeValue)
					}
				}
			default:
				return fmt.Errorf("invalid block page optional param name \"%s\"", optionalKey)
			}
		}
	}
	return nil
}

var wallarmAnnotations = parser.Annotation{
	Annotations: parser.AnnotationFields{
		wallarmModeAnnotation: {
			Validator: parser.ValidateOptions(
				[]string{"off", "monitoring", "safe_blocking", "block"}, true, true,
			),
			Scope:         parser.AnnotationScopeLocation,
			Risk:          parser.AnnotationRiskLow,
			Documentation: `Traffic processing mode`,
		},
		wallarmModeAllowOverrideAnnotation: {
			Validator: parser.ValidateOptions(
				[]string{"off", "strict", "on"}, true, true,
			),
			Scope:         parser.AnnotationScopeLocation,
			Risk:          parser.AnnotationRiskLow,
			Documentation: `Manages the ability to override the wallarm_mode values via filtering rules downloaded from the Wallarm Cloud (custom ruleset)`,
		},
		wallarmFallbackAnnotation: {
			Validator: parser.ValidateOptions(
				[]string{"off", "on"}, true, true,
			),
			Scope:         parser.AnnotationScopeLocation,
			Risk:          parser.AnnotationRiskLow,
			Documentation: `With the value set to on, NGINX has the ability to enter an emergency mode; if proton.db or custom ruleset cannot be downloaded, this setting disables the Wallarm module for the http, server, and location blocks, for which the data fails to download. NGINX keeps functioning`,
		},
		wallarmApplicationAnnotation: {
			AnnotationAliases: []string{wallarmInstanceAnnotation},
			Validator:         validateApplicationID,
			Scope:             parser.AnnotationScopeLocation,
			Risk:              parser.AnnotationRiskLow,
			Documentation:     `Unique identifier of the protected application to be used in the Wallarm Cloud. The value can be a positive integer except for 0`,
		},
		wallarmPartnerClientUUIDAnnotation: {
			Validator:     parser.ValidateRegex(regexp.MustCompile(`[0-9a-fA-F]{8}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{12}`), true),
			Scope:         parser.AnnotationScopeLocation,
			Risk:          parser.AnnotationRiskLow,
			Documentation: `Unique identifier of the tenant for the multi-tenant Wallarm node. The value should be a string in the UUID format`,
		},
		wallarmBlockPageAnnotation: {
			Validator:     validateBlockPage,
			Scope:         parser.AnnotationScopeLocation,
			Risk:          parser.AnnotationRiskLow,
			Documentation: `https://docs.wallarm.com/admin-en/configure-parameters-en/#wallarm_block_page`,
		},
		wallarmACLBlockPageAnnotation: {
			Validator:     func(string) error { return nil },
			Scope:         parser.AnnotationScopeLocation,
			Risk:          parser.AnnotationRiskMedium, // Deprecated + no validation
			Documentation: `Deprecated. Use "wallarm-block-page" instead`,
		},
		wallarmParseResponseAnnotation: {
			Validator: parser.ValidateOptions(
				[]string{"off", "on"}, true, true,
			),
			Scope:         parser.AnnotationScopeLocation,
			Risk:          parser.AnnotationRiskLow,
			Documentation: `Whether to analyze the application responses. Response analysis is required for vulnerability detection during passive detection and active threat verification`,
		},
		wallarmParseWebsocketAnnotation: {
			Validator: parser.ValidateOptions(
				[]string{"off", "on"}, true, true,
			),
			Scope:         parser.AnnotationScopeLocation,
			Risk:          parser.AnnotationRiskLow,
			Documentation: `Wallarm provides full WebSockets support under the API Security subscription plan. By default, the WebSockets' messages are not analyzed for attacks. To enable the feature, activate the API Security subscription plan and use the annotation`,
		},
		wallarmUnpackResponseAnnotation: {
			Validator: parser.ValidateOptions(
				[]string{"off", "on"}, true, true,
			),
			Scope:         parser.AnnotationScopeLocation,
			Risk:          parser.AnnotationRiskLow,
			Documentation: `Whether to decompress compressed data returned in the application response. Possible values are on (decompression is enabled) and off (decompression is disabled). This parameter is effective only if wallarm response parsing is on`,
		},
		wallarmParserDisableAnnotation: {
			Validator:     validateParserDisable,
			Scope:         parser.AnnotationScopeLocation,
			Risk:          parser.AnnotationRiskLow,
			Documentation: `Allows to disable parsers. The directive values correspond to the name of the parser to be disabled`,
		},
	},
}

type Config struct {
	Mode              string   `json:"mode"`
	ModeAllowOverride string   `json:"modeAllowOverride"`
	Fallback          string   `json:"fallback"`
	Instance          string   `json:"instance"`
	BlockPage         string   `json:"blockPage"`
	ACLBlockPage      string   `json:"aclBlockPage"`
	ParseResponse     string   `json:"parseResponse"`
	ParseWebsocket    string   `json:"parseWebsocket"`
	UnpackResponse    string   `json:"unpackResponse"`
	ParserDisable     []string `json:"parserDisable"`
	PartnerClientUUID string   `json:"partnerClientUUID"`
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
	if l1.ACLBlockPage != l2.ACLBlockPage {
		return false
	}
	if l1.PartnerClientUUID != l2.PartnerClientUUID {
		return false
	}

	return true
}

type wallarm struct {
	r                resolver.Resolver
	annotationConfig parser.Annotation
}

// NewParser creates a new wallarm module configuration annotation parser
func NewParser(r resolver.Resolver) parser.IngressAnnotation {
	return wallarm{
		r:                r,
		annotationConfig: wallarmAnnotations,
	}
}

// ParseAnnotations parses the annotations contained in the ingress
// rule used to configure upstream check parameters
func (a wallarm) Parse(ing *networking.Ingress) (interface{}, error) {
	var err error
	defBackend := a.r.GetDefaultBackend()
	config := &Config{}

	config.Mode, err = parser.GetStringAnnotation(wallarmModeAnnotation, ing, a.annotationConfig.Annotations)
	if err != nil {
		config.Mode = defBackend.WallarmMode
	}
	config.ModeAllowOverride, err = parser.GetStringAnnotation(wallarmModeAllowOverrideAnnotation, ing, a.annotationConfig.Annotations)
	if err != nil {
		config.ModeAllowOverride = defBackend.WallarmModeAllowOverride
	}
	config.Fallback, err = parser.GetStringAnnotation(wallarmFallbackAnnotation, ing, a.annotationConfig.Annotations)
	if err != nil {
		config.Fallback = defBackend.WallarmFallback
	}
	config.Instance, err = parser.GetStringAnnotation(wallarmApplicationAnnotation, ing, a.annotationConfig.Annotations)
	if err != nil {
		config.Instance = defBackend.WallarmInstance
	}
	config.PartnerClientUUID, err = parser.GetStringAnnotation(wallarmPartnerClientUUIDAnnotation, ing, a.annotationConfig.Annotations)
	if err != nil {
		config.PartnerClientUUID = defBackend.WallarmPartnerClientUUID
	}
	config.BlockPage, err = parser.GetStringAnnotation(wallarmBlockPageAnnotation, ing, a.annotationConfig.Annotations)
	if err != nil {
		config.BlockPage = defBackend.WallarmBlockPage
	}
	config.ACLBlockPage, err = parser.GetStringAnnotation(wallarmACLBlockPageAnnotation, ing, a.annotationConfig.Annotations)
	if err != nil {
		config.ACLBlockPage = defBackend.WallarmACLBlockPage
	}
	config.ParseResponse, err = parser.GetStringAnnotation(wallarmParseResponseAnnotation, ing, a.annotationConfig.Annotations)
	if err != nil {
		config.ParseResponse = defBackend.WallarmParseResponse
	}
	config.ParseWebsocket, err = parser.GetStringAnnotation(wallarmParseWebsocketAnnotation, ing, a.annotationConfig.Annotations)
	if err != nil {
		config.ParseWebsocket = defBackend.WallarmParseWebsocket
	}
	config.UnpackResponse, err = parser.GetStringAnnotation(wallarmUnpackResponseAnnotation, ing, a.annotationConfig.Annotations)
	if err != nil {
		config.UnpackResponse = defBackend.WallarmUnpackResponse
	}

	config.ParserDisable = []string{}
	pd, err := parser.GetStringAnnotation(wallarmParserDisableAnnotation, ing, a.annotationConfig.Annotations)
	if err != nil {
		config.ParserDisable = defBackend.WallarmParserDisable
	} else {
		config.ParserDisable = strings.Split(pd, ",")
	}
	for i, v := range config.ParserDisable {
		config.ParserDisable[i] = strings.TrimSpace(v)
	}

	return config, nil
}

func (a wallarm) GetDocumentation() parser.AnnotationFields {
	return a.annotationConfig.Annotations
}

func (a wallarm) Validate(anns map[string]string) error {
	maxrisk := parser.StringRiskToRisk(a.r.GetSecurityConfiguration().AnnotationsRiskLevel)
	return parser.CheckAnnotationRisk(anns, maxrisk, wallarmAnnotations.Annotations)
}
