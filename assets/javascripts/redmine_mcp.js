document.addEventListener("DOMContentLoaded", function () {
  const button = document.getElementById("copy-mcp-url");
  const url = document.getElementById("mcp-endpoint-url");
  const icon = document.getElementById("copy-icon");

  if (!button || !url || !icon) return;

  const COPY_ICON = icon.innerHTML;

  const CHECK_ICON = `
    <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
      <path
        d="M3 8.5L6.5 12L13 4.5"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"/>
    </svg>`;

  let resetTimer;

  async function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }

    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.left = "-9999px";

    document.body.appendChild(textarea);
    textarea.select();

    const copied = document.execCommand("copy");

    document.body.removeChild(textarea);

    if (!copied) {
      throw new Error("Clipboard copy failed.");
    }
  }

  button.addEventListener("click", async function () {
    if (button.disabled) return;

    try {
      button.disabled = true;

      await copyText(url.textContent.trim());

      icon.innerHTML = CHECK_ICON;

      clearTimeout(resetTimer);

      resetTimer = setTimeout(function () {
        icon.innerHTML = COPY_ICON;
        button.disabled = false;
      }, 1500);

    } catch (error) {
      console.error("Failed to copy MCP endpoint:", error);
      button.disabled = false;
    }
  });
});