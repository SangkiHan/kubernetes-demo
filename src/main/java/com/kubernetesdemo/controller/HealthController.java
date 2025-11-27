package com.kubernetesdemo.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class HealthController {

    @GetMapping("/info")
    public Map<String, Object> info() {
        Map<String, Object> response = new HashMap<>();
        response.put("application", "kubernetes-demo");
        response.put("version", "0.0.1-SNAPSHOT");
        response.put("description", "Spring Boot application deployed on Azure Kubernetes Service");
        
        Map<String, String> environment = new HashMap<>();
        environment.put("profile", System.getenv().getOrDefault("SPRING_PROFILES_ACTIVE", "default"));
        environment.put("java_version", System.getProperty("java.version"));
        environment.put("hostname", System.getenv().getOrDefault("HOSTNAME", "unknown"));
        
        response.put("environment", environment);
        response.put("timestamp", LocalDateTime.now());
        
        return response;
    }
}
