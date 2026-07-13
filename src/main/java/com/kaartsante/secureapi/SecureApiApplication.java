package com.kaartsante.secureapi;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.Map;
import java.time.Instant;

@SpringBootApplication
public class SecureApiApplication {
    public static void main(String[] args) {
        SpringApplication.run(SecureApiApplication.class, args);
    }
}

@RestController
class StatusController {

    @GetMapping("/api/v1/status")
    public Map<String, Object> getStatus() {
        return Map.of(
                "status", "UP",
                "message", "The Spring Boot API works perfectly",
                "timestamp", Instant.now().toString(),
                "secured", true);
    }
}
