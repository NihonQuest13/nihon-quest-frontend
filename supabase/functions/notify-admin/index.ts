// supabase/functions/notify-admin/index.ts
import { Resend } from "npm:resend";

// Récupérez votre clé API Resend depuis les secrets de Supabase
// Le "!" à la fin indique à TypeScript que nous sommes sûrs que cette variable existera.
const resend = new Resend(Deno.env.get("RESEND_API_KEY")!);
const ADMIN_EMAIL = "nathangrondin682@gmail.com"; // Votre email

Deno.serve(async (req) => {
  // Gérer la requête CORS preflight, nécessaire pour que l'appel depuis le navigateur fonctionne
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const { firstName, lastName, email } = await req.json();

    // Envoi de l'email via Resend
    const { data, error } = await resend.emails.send({
      from: "Validation <onboarding@resend.dev>", // Ou votre domaine vérifié
      to: [ADMIN_EMAIL],
      subject: "Nouvelle demande d'inscription à valider",
      html: `
        <h1>Nouvelle demande d'inscription</h1>
        <p>Une nouvelle personne souhaite s'inscrire :</p>
        <ul>
          <li><strong>Prénom :</strong> ${firstName}</li>
          <li><strong>Nom :</strong> ${lastName}</li>
          <li><strong>Email :</strong> ${email}</li>
        </ul>
        <p>Connectez-vous à votre dashboard Supabase pour approuver ou rejeter cette demande dans la table "profiles".</p>
      `,
    });

    if (error) {
      console.error({ error });
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { 
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*" 
        },
      });
    }

    return new Response(JSON.stringify({ message: "Notification sent." }), {
      headers: { 
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*" 
      },
      status: 200,
    });
  } catch (err) {
    return new Response(String(err?.message ?? err), { 
      status: 500,
      headers: { "Access-Control-Allow-Origin": "*" }
    });
  }
});