"""Reference outputs from the Python prototype (scikit-learn) for the Swift parity tests.

Run from the repo root with the prototype's venv:  .venv/bin/python LidTapApp/Tests/make_fixtures.py
"""
import json
import sys
from pathlib import Path

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.neighbors import KNeighborsClassifier, NearestCentroid
from sklearn.preprocessing import StandardScaler

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lidtap import features  # noqa: E402

here = Path(__file__).parent / "Fixtures"
ds = json.loads((here / "dataset_2x2.json").read_text())
X = np.array([features.extract(s["g"], s["a"]) for s in ds["samples"]])
y = np.array([s["label"] for s in ds["samples"]])
train, test = np.arange(len(y)) % 2 == 0, np.arange(len(y)) % 2 == 1
sc = StandardScaler().fit(X[train])
Z = sc.transform(X) * features.WEIGHTS
out = {
    "features": X.tolist(),
    "split_predictions": {
        "knn": KNeighborsClassifier(3, weights="distance").fit(Z[train], y[train]).predict(Z[test]).tolist(),
        "centroid": NearestCentroid().fit(Z[train], y[train]).predict(Z[test]).tolist(),
        "logreg": LogisticRegression(max_iter=3000).fit(Z[train], y[train]).predict(Z[test]).tolist(),
    },
    "test_labels": y[test].tolist(),
    "percentiles": [
        {"values": v, "q": q, "result": float(np.percentile(v, q))}
        for v, q in [([1, 2, 3, 4], 95), ([5.0], 50), ([3, 1, 2], 50), ([0.1, 0.4, 0.2, 0.9, 0.5], 95), ([2, 8], 25)]
    ],
}
(here / "python_reference.json").write_text(json.dumps(out))
print("features", X.shape, "written", here / "python_reference.json")
