import React, { useState } from "react";
import "bootstrap/dist/css/bootstrap.min.css";

const AmplifyForm = () => {
  const [query, setQuery] = useState("");
  const [lang, setLang] = useState("");
  const [response, setResponse] = useState("");
  const [loading, setLoading] = useState(false);
  

  // Helper function to check date format and validity
  const handleSubmit = async () => {
    if (!query) {
      alert("QUERY is required!");
      return;
    }

    setLoading(true);

    try {
      // Construct the URL with proper query parameters
      let url = `${process.env.REACT_APP_API_URL}?query=${encodeURIComponent(query)}`;

      if (lang) {
        url += `&language=${encodeURIComponent(lang)}`;
      }

      // Make a single GET request with query parameters
      const response = await fetch(url, {
        method: "GET",
        headers: {
          "Accept": "application/json",
        },
      });

      if (!response.ok) {
        throw new Error(`Request failed: ${response.statusText}`);
      }
      
      const data = await response.json();
      
      console.log(data)

      // Extract sentiment breakdown
      const sentimentData = data.ddbResponse?.news?.results?.breakdown;

      // Format the response to display the overall sentiment and breakdowns
      const formattedResponse = `
        Overall Sentiment: ${data.ddbResponse?.news?.results?.overallSentiment}
        
        Sentiment Breakdown:
        - Positive: ${sentimentData.POSITIVE}%
        - Negative: ${sentimentData.NEGATIVE}%
        - Neutral: ${sentimentData.NEUTRAL}%
        - Mixed: ${sentimentData.MIXED}%
      `;

      setResponse(formattedResponse);
    } catch (error) {
      setResponse("Error: " + error.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="container mt-5">
      <div className="card p-4 mx-auto" style={{ maxWidth: "400px" }}>
        <div className="mb-3">
          <input
            type="text"
            className="form-control"
            placeholder="QUERY (Required)"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <div className="mb-3">
          <input
            type="text"
            className="form-control"
            placeholder="LANG (en, es, zh, ja)"	
            value={lang}
            onChange={(e) => setLang(e.target.value)}
          />
        </div>
        <button
          className="btn btn-primary w-100"
          onClick={handleSubmit}
          disabled={loading}
        >
          {loading ? "Submitting..." : "Submit"}
        </button>
        <div className="mt-3" style={{ fontSize: "16px" }}>
          RESULT
        </div>
        <div
          className="mt-3 p-3 border rounded bg-light"
          style={{ wordWrap: "break-word", whiteSpace: "pre-wrap" }}
        >
          {response}
        </div>
      </div>
    </div>
  );
};

export default AmplifyForm;