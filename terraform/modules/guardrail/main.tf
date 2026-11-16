############################################################################
# Guardrail: the AWS-side control for generative AI answers, used by the
# guard gateway. A guardrail is created, published as a numbered immutable
# version, and the Lambda is pinned to that version, so what was tested is
# what runs.
#
# Why have this when CXone's AI agents have built-in safety instructions?
# Because built-in controls are the vendor's; this one is YOURS: you can test
# it with a fixed set of prompts, version it, alarm on it and show an
# auditor the exact rules. See docs/BUILD-MANUAL.md, Part 12.
############################################################################
resource "aws_bedrock_guardrail" "this" {
  name                      = "${var.prefix}-cxone-guard"
  description               = "Insurer guardrail: no advice, no promises of payment, no card data, harmful content and prompt attacks filtered."
  blocked_input_messaging   = var.blocked_message
  blocked_outputs_messaging = var.blocked_message

  topic_policy_config {
    topics_config {
      name       = "financial_investment_advice"
      type       = "DENY"
      definition = "Recommendations about shares, investments, superannuation, loans or how to invest or spend money."
      examples = [
        "Which shares should I buy with my insurance payout?",
        "Should I put my claim money into a term deposit?",
      ]
    }
    topics_config {
      name       = "legal_advice"
      type       = "DENY"
      definition = "Advice about legal rights, liability, suing someone, fault in an accident, or what to say in court or to a tribunal."
      examples = [
        "Can I sue the other driver?",
        "Who is legally at fault in my accident?",
      ]
    }
    topics_config {
      name       = "medical_advice"
      type       = "DENY"
      definition = "Diagnosis, treatment or medication advice about injuries or health conditions."
      examples = [
        "What painkillers should I take for my neck injury?",
        "Do I need an X-ray after the crash?",
      ]
    }
    topics_config {
      name       = "claim_outcome_promises"
      type       = "DENY"
      definition = "Statements that a claim will be approved or paid, that a loss is covered, or how much will be paid, before a person has assessed it."
      examples = [
        "Will my claim definitely be paid?",
        "Tell me my storm damage is covered and how much I will get.",
      ]
    }
  }

  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "INSULTS"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "MISCONDUCT"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    # Prompt attacks are an input-side control. Output strength must be NONE.
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }
  }

  word_policy_config {
    managed_word_lists_config {
      type = "PROFANITY"
    }
  }

  sensitive_information_policy_config {
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_CVV"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_EXPIRY"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "PASSWORD"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "PIN"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "DRIVER_ID"
      action = "ANONYMIZE"
    }
  }

  # Grounding: only bites when a request supplies a grounding source (the
  # policy wording or knowledge-base passage the answer must come from).
  contextual_grounding_policy_config {
    filters_config {
      type      = "GROUNDING"
      threshold = 0.75
    }
    filters_config {
      type      = "RELEVANCE"
      threshold = 0.5
    }
  }
}

# A numbered, immutable snapshot. The Lambda uses this, never DRAFT.
# To ship a change: edit the guardrail above, change the description below, apply.
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "v1: four denied topics, six content filters, profanity, eight PII entities, grounding"
}
