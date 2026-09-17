/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jms.annotation.JmsListener;
import org.springframework.samples.petclinic.messaging.dto.RpcResponse;
import org.springframework.stereotype.Component;

/**
 * TIBCO JMS replier. Listens on all six RPC request queues, dispatches each message to
 * {@link PetClinicRpcService}, and routes each JSON reply to the temporary queue set by
 * the frontend in the JMSReplyTo header.
 */
@Component
public class TibcoRpcListener {

	private static final Logger log = LoggerFactory.getLogger(TibcoRpcListener.class);

	private final PetClinicRpcService service;

	private final ObjectMapper json;

	public TibcoRpcListener(PetClinicRpcService service, ObjectMapper json) {
		this.service = service;
		this.json = json;
	}

	@JmsListener(destination = RpcTopics.PREFIX + RpcTopics.OWNER_FIND_BY_ID)
	public String handleOwnerFindById(String body) {
		return dispatch(RpcTopics.OWNER_FIND_BY_ID, body);
	}

	@JmsListener(destination = RpcTopics.PREFIX + RpcTopics.OWNER_FIND_BY_LAST_NAME)
	public String handleOwnerFindByLastName(String body) {
		return dispatch(RpcTopics.OWNER_FIND_BY_LAST_NAME, body);
	}

	@JmsListener(destination = RpcTopics.PREFIX + RpcTopics.OWNER_SAVE)
	public String handleOwnerSave(String body) {
		return dispatch(RpcTopics.OWNER_SAVE, body);
	}

	@JmsListener(destination = RpcTopics.PREFIX + RpcTopics.PETTYPE_FIND_ALL)
	public String handlePetTypeFindAll(String body) {
		return dispatch(RpcTopics.PETTYPE_FIND_ALL, body);
	}

	@JmsListener(destination = RpcTopics.PREFIX + RpcTopics.VET_FIND_ALL)
	public String handleVetFindAll(String body) {
		return dispatch(RpcTopics.VET_FIND_ALL, body);
	}

	@JmsListener(destination = RpcTopics.PREFIX + RpcTopics.VET_FIND_ALL_PAGED)
	public String handleVetFindAllPaged(String body) {
		return dispatch(RpcTopics.VET_FIND_ALL_PAGED, body);
	}

	private String dispatch(String operation, String body) {
		log.debug("RPC request for operation '{}'", operation);
		RpcResponse response = service.dispatch(operation, body);
		try {
			return json.writeValueAsString(response);
		}
		catch (JsonProcessingException ex) {
			log.error("Failed to serialize RPC reply for operation '{}'", operation, ex);
			try {
				return json.writeValueAsString(RpcResponse.error("SERIALIZATION_ERROR", ex.getMessage()));
			}
			catch (JsonProcessingException ignored) {
				return "{\"success\":false,\"errorCode\":\"SERIALIZATION_ERROR\"}";
			}
		}
	}

}
