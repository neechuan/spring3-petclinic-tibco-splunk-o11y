/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 */
package org.springframework.samples.petclinic.messaging;

/**
 * TIBCO JMS queue constants defining the request/reply RPC contract between the PetClinic
 * frontend and backend. Queues use dot notation (JMS/TIBCO convention).
 */
public final class RpcTopics {

	/** Common topic prefix for every RPC request. */
	public static final String PREFIX = "petclinic.rpc.";

	public static final String OWNER_FIND_BY_ID = "owner.findById";

	public static final String OWNER_FIND_BY_LAST_NAME = "owner.findByLastName";

	public static final String OWNER_SAVE = "owner.save";

	public static final String PETTYPE_FIND_ALL = "pettype.findAll";

	public static final String VET_FIND_ALL = "vet.findAll";

	public static final String VET_FIND_ALL_PAGED = "vet.findAllPaged";

	/** Reply queue (not used since we use temporary queues). */
	public static final String REPLIES_TOPIC = "petclinic.rpc.replies";

	private RpcTopics() {
	}

}
