package com.kubernetesdemo.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

@RestController
public class DemoController {

    @GetMapping("/")
    public String home() {
        return "Hello from Spring Boot on AKS v2! 🚀🚀";
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }

    @GetMapping("/info")
    public String info() throws UnknownHostException {
        String hostname = InetAddress.getLocalHost().getHostName();
        String currentTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        
        return String.format(
            "Demo Application\n" +
            "Hostname: %s\n" +
            "Time: %s\n" +
            "Version: 1.0.0",
            hostname, currentTime
        );
    }

    @GetMapping("/api/hello")
    public HelloResponse hello() {
        return new HelloResponse("Hello from AKS!", LocalDateTime.now());
    }
    
    static class HelloResponse {
        public String message;
        public LocalDateTime timestamp;
        
        public HelloResponse(String message, LocalDateTime timestamp) {
            this.message = message;
            this.timestamp = timestamp;
        }
    }
}
