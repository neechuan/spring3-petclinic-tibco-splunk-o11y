/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging;

import org.springframework.context.annotation.Configuration;
import org.springframework.jms.annotation.EnableJms;

@Configuration
@EnableJms
public class TibcoConfig {
	// Let standard Spring Boot JMS auto-configuration wire the ConnectionFactory,
	// JmsTemplate, and listener container factory.
}
