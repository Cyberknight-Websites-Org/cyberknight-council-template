// Newsletter subscription form handler

// Initialize newsletter form
function initNewsletterForm() {
  const form = document.querySelector('.newsletter-subscribe-form');
  if (!form) return;

  form.addEventListener('submit', handleNewsletterSubmit);
}

// Handle form submission
async function handleNewsletterSubmit(event) {
  event.preventDefault();

  const form = event.target;
  const submitButton = form.querySelector('.submit-button');
  const feedbackDiv = document.getElementById('newsletter-feedback');

  // Disable submit button during processing
  submitButton.disabled = true;
  submitButton.textContent = 'Subscribing...';

  // Collect form data
  const formData = {
    email: form.querySelector('#email').value.trim(),
    name: form.querySelector('#name').value.trim(),
    phone: form.querySelector('#phone').value.trim(),
    is_human: form.querySelector('#is_human').checked
  };

  try {
    const result = await subscribeToNewsletter(councilData.councilNumber, formData);

    if (result.success) {
      showFeedback(feedbackDiv, 'success', result.message);
      form.reset(); // Clear form on success
    } else {
      showFeedback(feedbackDiv, 'error', result.error);
    }
  } catch (error) {
    showFeedback(feedbackDiv, 'error', 'An unexpected error occurred. Please try again.');
  } finally {
    // Re-enable submit button
    submitButton.disabled = false;
    submitButton.textContent = 'Subscribe to Newsletter';
  }
}

// Make API call to subscribe
async function subscribeToNewsletter(councilNumber, formData) {
  const payload = {
    email: formData.email,
    name: formData.name || "",
    phone: formData.phone || "",
    is_human: formData.is_human || false
  };

  try {
    const response = await fetch(
      `https://secure.cyberknight-websites.com/public_api/${councilNumber}/newsletter_subscribe`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      }
    );

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || "Subscription failed");
    }

    return {
      success: true,
      message: "Thank you for subscribing! Check your email for confirmation."
    };
  } catch (error) {
    return {
      success: false,
      error: error.message || "Failed to subscribe. Please try again."
    };
  }
}

// Display feedback message
function showFeedback(element, type, message) {
  element.className = `newsletter-feedback ${type}`;
  element.textContent = message;
  element.style.display = 'block';

  // Auto-hide success messages after 5 seconds
  if (type === 'success') {
    setTimeout(() => {
      element.style.display = 'none';
    }, 5000);
  }
}
