{
	"title": $subscriptionTitle,
	"product": {
		"id": $productId
	},
	"plan": {
		"id": $planId
	},
	"owner": {
		"id": $userGuid,
		"type": "user",
		"context": {
			"type": "team",
			"id": $teamId
		}
	}
}