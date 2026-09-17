/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging;

import java.util.UUID;
import jakarta.jms.JMSException;
import jakarta.jms.Message;
import jakarta.jms.MessageConsumer;
import jakarta.jms.MessageProducer;
import jakarta.jms.Queue;
import jakarta.jms.TemporaryQueue;
import jakarta.jms.TextMessage;

import com.fasterxml.jackson.databind.JavaType;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.type.TypeFactory;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jms.core.JmsTemplate;
import org.springframework.stereotype.Component;

/**
 * Synchronous request/reply client for the backend over TIBCO EMS/BW (JMS).
 */
@Component
public class TibcoRpcClient {

	private static final Logger log = LoggerFactory.getLogger(TibcoRpcClient.class);

	private final JmsTemplate jmsTemplate;

	private final ObjectMapper json;

	@Value("${tibco.request.timeout-ms:10000}")
	private long timeoutMs;

	public TibcoRpcClient(JmsTemplate jmsTemplate, ObjectMapper json) {
		this.jmsTemplate = jmsTemplate;
		this.json = json;
	}

	public TypeFactory getTypeFactory() {
		return json.getTypeFactory();
	}

	public <T> T call(String operation, Object payload, Class<T> type) {
		return convert(callRaw(operation, payload), getTypeFactory().constructType(type));
	}

	public <T> T call(String operation, Object payload, JavaType type) {
		return convert(callRaw(operation, payload), type);
	}

	private <T> T convert(JsonNode node, JavaType type) {
		if (node == null || node.isNull()) {
			return null;
		}
		return json.convertValue(node, type);
	}

	public JsonNode callRaw(String operation, Object payload) {
		String queueName = RpcTopics.PREFIX + operation;
		try {
			String body = (payload == null) ? "{}" : json.writeValueAsString(payload);
			String replyContent = jmsTemplate.execute(session -> {
				Queue requestQueue = session.createQueue(queueName);
				TemporaryQueue replyQueue = session.createTemporaryQueue();
				try (MessageProducer producer = session.createProducer(requestQueue);
					 MessageConsumer consumer = session.createConsumer(replyQueue)) {
					
					TextMessage message = session.createTextMessage(body);
					message.setJMSReplyTo(replyQueue);
					String correlationId = UUID.randomUUID().toString();
					message.setJMSCorrelationID(correlationId);
					
					producer.send(message);
					Message reply = consumer.receive(timeoutMs);
					if (reply instanceof TextMessage textMessage) {
						return textMessage.getText();
					} else if (reply != null) {
						throw new JMSException("Received non-text reply message");
					} else {
						throw new JMSException("RPC timeout waiting for response on " + queueName);
					}
				} finally {
					try {
						replyQueue.delete();
					} catch (JMSException e) {
						log.warn("Failed to delete temporary reply queue", e);
					}
				}
			}, true);

			RpcResponse response = json.readValue(replyContent, RpcResponse.class);
			if (!response.isSuccess()) {
				throw toException(response);
			}
			return response.getPayload();
		}
		catch (Exception ex) {
			throw new IllegalStateException("TIBCO RPC call failed for operation '" + operation + "'", ex);
		}
	}

	private RuntimeException toException(RpcResponse response) {
		String code = response.getErrorCode();
		String message = response.getErrorMessage();
		if ("DUPLICATE_PET_NAME".equals(code)) {
			return new DataIntegrityViolationException("unique_owner_pet_name violation: " + message);
		}
		return new IllegalStateException("Backend RPC error [" + code + "]: " + message);
	}

}
