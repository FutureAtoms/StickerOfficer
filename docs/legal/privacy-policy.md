# StickerOfficer Privacy Policy

**Effective Date:** March 2026
**Last Updated:** March 2026

## 1. Information We Collect

### Device Identifier
We generate a random device UUID on first launch. This is stored locally on your device and used to authenticate your session. We do not collect your name, email, phone number, or any personal identifiers.

### AI Prompts
When you use the AI sticker generation feature, your text prompt is sent to our server, which forwards it to a third-party AI image generation service (Hugging Face). Prompts are filtered for prohibited content before being sent. We do not store prompts after processing.

### Usage Data
We collect anonymous usage data including:
- Sticker packs created, liked, and downloaded (counts only)
- Challenge participation (submissions and votes)
- Content reports you submit

### IP Address
Your IP address is temporarily used for rate limiting to prevent abuse. It is not stored persistently or associated with your device identifier.

## 2. How We Use Your Information

- **Authentication:** Your device UUID creates an anonymous session token (JWT) so you can publish, like, and interact with content.
- **Content Delivery:** To serve sticker packs and challenge content.
- **Moderation:** To process content reports and enforce community guidelines.
- **Rate Limiting:** To prevent abuse of AI generation and other features.

## 3. Data Storage

- **Backend:** Cloudflare Workers with D1 (SQLite) for structured data and R2 for sticker images.
- **Location:** Data is processed at Cloudflare edge locations globally.
- **Local Storage:** Your device UUID and authentication token are stored securely on your device using encrypted storage.

## 4. Third-Party Services

- **Hugging Face:** AI image generation. Subject to [Hugging Face Privacy Policy](https://huggingface.co/privacy).
- **Cloudflare:** Infrastructure provider. Subject to [Cloudflare Privacy Policy](https://www.cloudflare.com/privacypolicy/).
- **WhatsApp:** Sticker export uses WhatsApp's public sticker integration API. No data is shared with WhatsApp beyond the sticker images you choose to export.

## 5. Data Retention

- Device records and published content are retained indefinitely while the service operates.
- Content removed due to moderation is deleted within 30 days.
- Rate limiting data expires automatically within 1 hour.

## 6. Your Rights

- **Delete your content:** You can delete any sticker packs you have published.
- **Block users:** You can block other users whose content you do not wish to see.
- **Data deletion:** Contact us to request deletion of your device record and all associated data.

## 7. Children's Privacy

StickerOfficer is not directed at children under 13. We do not knowingly collect information from children under 13.

## 8. Changes to This Policy

We may update this policy from time to time. Changes will be posted in the app and on our website.

## 9. Contact

For privacy questions or data deletion requests:
**Email:** privacy@futureatoms.com
