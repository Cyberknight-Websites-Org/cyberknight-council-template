// Prayer request form handler

function initPrayerRequestForm() {
  const form = document.querySelector('.prayer-request-form');
  if (!form) return;

  form.addEventListener('submit', handlePrayerRequestSubmit);

  const emailField = form.querySelector('#requester_email');
  const phoneField = form.querySelector('#requester_phone');

  function clearContactValidity() {
    if (emailField.value.trim() || phoneField.value.trim()) {
      emailField.setCustomValidity('');
      phoneField.setCustomValidity('');
    }
  }

  emailField.addEventListener('input', clearContactValidity);
  phoneField.addEventListener('input', clearContactValidity);
}

async function handlePrayerRequestSubmit(event) {
  event.preventDefault();

  const form = event.target;
  const submitButton = form.querySelector('.submit-button');
  const feedbackDiv = document.getElementById('prayer-request-feedback');
  const councilNumber = (typeof councilData !== 'undefined' && councilData.councilNumber) || '';

  if (!councilNumber) {
    showPrayerRequestFeedback(feedbackDiv, 'error', 'Unable to submit request: missing council information.');
    return;
  }

  const emailField = form.querySelector('#requester_email');
  const phoneField = form.querySelector('#requester_phone');

  if (!form.checkValidity()) {
    form.reportValidity();
    return;
  }

  const emailValue = emailField.value.trim();
  const phoneValue = phoneField.value.trim();

  if (!emailValue && !phoneValue) {
    const message = 'Please provide an email address or phone number so we can follow up if needed.';
    emailField.setCustomValidity(message);
    phoneField.setCustomValidity(message);
    form.reportValidity();
    return;
  }

  const originalButtonText = submitButton.textContent;
  submitButton.disabled = true;
  submitButton.textContent = 'Submitting...';

  const payload = {
    recipient_name: form.querySelector('#recipient_name').value.trim(),
    reason: form.querySelector('#reason').value.trim(),
    requester_email: emailValue,
    requester_phone: phoneValue,
    is_human: form.querySelector('#is_human').checked
  };

  try {
    const result = await submitPrayerRequest(councilNumber, payload);

    if (result.success) {
      showPrayerRequestFeedback(feedbackDiv, 'success', result.message);
      form.reset();
    } else {
      showPrayerRequestFeedback(feedbackDiv, 'error', result.error);
    }
  } catch (error) {
    showPrayerRequestFeedback(feedbackDiv, 'error', 'An unexpected error occurred. Please try again.');
  } finally {
    submitButton.disabled = false;
    submitButton.textContent = originalButtonText;
  }
}

async function submitPrayerRequest(councilNumber, payload) {
  try {
    const response = await fetch(
      `https://secure.cyberknight-websites.com/public_forms/${councilNumber}/prayer_requests`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      }
    );

    let data = {};
    const text = await response.text();
    if (text) {
      try {
        data = JSON.parse(text);
      } catch (parseError) {
        // Non-JSON response body is not safe to display; leave data empty
        // so callers fall back to generic messages.
      }
    }

    if (!response.ok) {
      return {
        success: false,
        error: getPrayerRequestSafeError(data) || 'Unable to process your request. Please check your input and try again.'
      };
    }

    return {
      success: true,
      message: getPrayerRequestSafeSuccessMessage(data) || 'Your prayer intention has been submitted. Thank you!'
    };
  } catch (error) {
    return {
      success: false,
      error: 'Unable to connect to the server. Please check your connection and try again.'
    };
  }
}

function getPrayerRequestSafeSuccessMessage(data) {
  if (!data || typeof data !== 'object') return null;
  const message = data.message;
  return typeof message === 'string' && message.trim().length > 0 ? message.trim() : null;
}

function getPrayerRequestSafeError(data) {
  if (!data || typeof data !== 'object') return null;
  const error = data.error;
  return typeof error === 'string' && error.trim().length > 0 ? error.trim() : null;
}

function showPrayerRequestFeedback(element, type, message) {
  if (!element) return;

  element.className = `newsletter-feedback ${type}`;
  element.textContent = message;
  element.style.display = 'block';

  if (type === 'success') {
    setTimeout(() => {
      element.style.display = 'none';
    }, 5000);
  }
}
