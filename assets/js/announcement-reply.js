// Announcement reply form handler

function initAnnouncementReplyForm() {
  const form = document.querySelector('.announcement-reply-form');
  if (!form) return;

  form.addEventListener('submit', handleAnnouncementReplySubmit);
}

async function handleAnnouncementReplySubmit(event) {
  event.preventDefault();

  const form = event.target;
  const submitButton = form.querySelector('.submit-button');
  const feedbackDiv = document.getElementById('reply-feedback');
  const announcementId = form.dataset.announcementId;
  const councilNumber = (typeof councilData !== 'undefined' && councilData.councilNumber) || '';

  if (!councilNumber || !announcementId) {
    showReplyFeedback(feedbackDiv, 'error', 'Unable to send reply: missing council or announcement information.');
    return;
  }

  const originalButtonText = submitButton.textContent;
  submitButton.disabled = true;
  submitButton.textContent = 'Sending...';

  const payload = {
    name: form.querySelector('#reply-name').value.trim(),
    email: form.querySelector('#reply-email').value.trim(),
    message: form.querySelector('#reply-message').value.trim(),
    is_human: form.querySelector('#reply-is-human').checked
  };

  try {
    const result = await submitAnnouncementReply(councilNumber, announcementId, payload);

    if (result.success) {
      showReplyFeedback(feedbackDiv, 'success', result.message);
      form.reset();
    } else {
      showReplyFeedback(feedbackDiv, 'error', result.error);
    }
  } catch (error) {
    showReplyFeedback(feedbackDiv, 'error', 'An unexpected error occurred. Please try again.');
  } finally {
    submitButton.disabled = false;
    submitButton.textContent = originalButtonText;
  }
}

async function submitAnnouncementReply(councilNumber, announcementId, payload) {
  try {
    const response = await fetch(
      `https://secure.cyberknight-websites.com/public_forms/${councilNumber}/announcements/${announcementId}/reply`,
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
        error: getUserSafeError(data) || 'Failed to send reply. Please try again.'
      };
    }

    return {
      success: true,
      message: getUserSafeSuccessMessage(data) || 'Your reply has been sent. Thank you!'
    };
  } catch (error) {
    return {
      success: false,
      error: 'Unable to connect to the server. Please check your connection and try again.'
    };
  }
}

function getUserSafeSuccessMessage(data) {
  if (!data || typeof data !== 'object') return null;
  const message = data.message;
  return typeof message === 'string' && message.trim().length > 0 ? message.trim() : null;
}

function getUserSafeError(data) {
  if (!data || typeof data !== 'object') return null;
  const error = data.error;
  return typeof error === 'string' && error.trim().length > 0 ? error.trim() : null;
}

function showReplyFeedback(element, type, message) {
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

// Initialize when the DOM is ready
document.addEventListener('DOMContentLoaded', initAnnouncementReplyForm);
