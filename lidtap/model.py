"""Zone classifiers, cross-validated evaluation and open-set rejection."""

import random
import warnings
from collections import Counter

import numpy as np
from sklearn.base import BaseEstimator, TransformerMixin
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import StratifiedKFold, cross_val_predict
from sklearn.neighbors import KNeighborsClassifier, NearestCentroid
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC

from . import features
from .detector import TRIG

NOISE = "noise"
warnings.filterwarnings("ignore", module="sklearn.neighbors._nearest_centroid")


class Weight(BaseEstimator, TransformerMixin):
    def __init__(self, w=None):
        self.w = w

    def fit(self, X, y=None):
        self.n_features_in_ = X.shape[1]
        return self

    def transform(self, X):
        return X * self.w


KINDS = {
    "knn": ("k-nearest neighbours", lambda: KNeighborsClassifier(n_neighbors=3, weights="distance")),
    "centroid": ("Nearest centroid", NearestCentroid),
    "svm": ("SVM (RBF)", lambda: SVC(C=10, gamma="scale")),
    "logreg": ("Logistic regression", lambda: LogisticRegression(max_iter=3000)),
    "rf": ("Random forest", lambda: RandomForestClassifier(n_estimators=120, random_state=0)),
}


def pipeline(kind):
    return make_pipeline(StandardScaler(), Weight(features.WEIGHTS), KINDS[kind][1]())


def zone_label(i):
    return f"z{i}"


def zone_index(label):
    return int(label[1:]) if label.startswith("z") else None


def layouts(rows, cols):
    """Coarser layouts a grid can be merged into: name -> label mapper (None drops the sample)."""

    def by(fn):
        return lambda lab: lab if lab == NOISE else fn(*divmod(zone_index(lab), cols))

    def halves(n, i):  # 0/1 for the two halves; the middle line of an odd grid is dropped
        if n % 2 and i == n // 2:
            return None
        return int(i >= n / 2)

    out = {"Full grid": lambda lab: lab}
    if cols >= 3:
        out["Columns"] = by(lambda r, c: f"col{c}")
    if cols >= 2:
        out["Left / right"] = by(lambda r, c: None if halves(cols, c) is None else "LR"[halves(cols, c)])
    if rows >= 3:
        out["Rows"] = by(lambda r, c: f"row{r}")
    if rows >= 2:
        out["Top / bottom"] = by(lambda r, c: None if halves(rows, r) is None else "TB"[halves(rows, r)])
    if rows >= 2 and cols >= 2 and (rows, cols) != (2, 2):
        def quad(r, c):
            hr, hc = halves(rows, r), halves(cols, c)
            return None if hr is None or hc is None else f"q{hr}{hc}"
        out["Corners 2×2"] = by(quad)
    return out


def _cv_predict(kind, X, y):
    m = min(Counter(y).values())
    if m < 2 or len(set(y)) < 2:
        return None
    cv = StratifiedKFold(n_splits=min(5, m), shuffle=True, random_state=0)
    return cross_val_predict(pipeline(kind), X, y, cv=cv)


def _remap(X, y, fn):
    keep = [i for i, lab in enumerate(y) if fn(lab) is not None]
    return X[keep], np.array([fn(y[i]) for i in keep])


def _learning_curve(kind, X, y, repeats=5):
    counts = Counter(y)
    m = min(counts.values())
    out = []
    for n in [2, 3, 5, 8, 10, 15, 20, 30, 40]:
        if n >= m:
            break
        accs = []
        for rep in range(repeats):
            rng = random.Random(rep)
            train, test = [], []
            for c in counts:
                idx = [i for i, lab in enumerate(y) if lab == c]
                rng.shuffle(idx)
                train += idx[:n]
                test += idx[n:]
            pred = pipeline(kind).fit(X[train], y[train]).predict(X[test])
            accs.append(float(np.mean(pred == y[test])))
        out.append({"n": n, "acc": float(np.mean(accs))})
    return out


def _signatures(samples):
    """Mean strength-normalised gyro waveform per label, aligned on the trigger."""
    groups = {}
    for s in samples:
        g = np.asarray(s["g"], float)
        peak = np.linalg.norm(g, axis=1).max() or 1.0
        groups.setdefault(s["label"], []).append(g / peak)
    return {lab: np.round(np.mean(gs, axis=0)[TRIG - 16: TRIG + 96: 2], 3).tolist() for lab, gs in groups.items()}


def evaluate(samples, rows, cols):
    X = np.array([s["f"] for s in samples])
    y = np.array([s["label"] for s in samples])
    labels = sorted(set(y), key=lambda lab: (lab == NOISE, zone_index(lab) or 0))
    lays = layouts(rows, cols)
    results = []
    preds = {}
    for kind, (name, _) in KINDS.items():
        row = {"kind": kind, "name": name, "acc": {}}
        for lay, fn in lays.items():
            Xl, yl = _remap(X, y, fn)
            p = _cv_predict(kind, Xl, yl)
            row["acc"][lay] = None if p is None else float(np.mean(p == yl))
            if lay == "Full grid":
                preds[kind] = p
        results.append(row)
    scored = [r for r in results if r["acc"]["Full grid"] is not None]
    best = max(scored, key=lambda r: r["acc"]["Full grid"])["kind"] if scored else "knn"

    report = {"n": len(samples), "labels": labels, "grid": {"rows": rows, "cols": cols},
              "layouts": list(lays), "models": results, "best": best,
              "counts": {lab: int((y == lab).sum()) for lab in labels},
              "signatures": _signatures(samples)}
    p = preds.get(best)
    if p is not None:
        idx = {lab: i for i, lab in enumerate(labels)}
        cm = np.zeros((len(labels), len(labels)), int)
        for t, q in zip(y, p):
            cm[idx[t], idx[q]] += 1
        report["confusion"] = cm.tolist()
        report["learning"] = _learning_curve(best, X, y)
    Z = StandardScaler().fit_transform(X) * features.WEIGHTS
    Z -= Z.mean(0)
    if len(Z) >= 3:
        _, _, vt = np.linalg.svd(Z, full_matrices=False)
        pts = Z @ vt[:2].T
        report["pca"] = [[round(float(a), 3), round(float(b), 3), lab] for (a, b), lab in zip(pts, y)]
    return report


class ZoneModel:
    def __init__(self, kind, samples):
        X = np.array([s["f"] for s in samples])
        self.y = np.array([s["label"] for s in samples])
        self.kind = kind
        self.pipe = pipeline(kind).fit(X, self.y)
        self.Z = self.pipe[:-1].transform(X)
        # Typical spacing inside each class: 95th percentile of nearest same-class neighbour distance.
        self.radius = {}
        for c in set(self.y):
            Zc = self.Z[self.y == c]
            if len(Zc) < 3:
                self.radius[c] = np.inf
                continue
            D = np.linalg.norm(Zc[:, None] - Zc[None], axis=2)
            np.fill_diagonal(D, np.inf)
            self.radius[c] = float(np.percentile(D.min(1), 95)) or np.inf

    def _confidence(self, z):
        clf = self.pipe[-1]
        if hasattr(clf, "predict_proba"):
            try:
                return float(clf.predict_proba(z).max())
            except Exception:
                pass
        if hasattr(clf, "decision_function"):
            d = np.atleast_1d(clf.decision_function(z)[0])
            if d.size == 1:
                return float(1 / (1 + np.exp(-abs(d[0]))))
            e = np.exp(d - d.max())
            return float(e.max() / e.sum())
        return 1.0

    def predict(self, f, reject_factor):
        z = self.pipe[:-1].transform(np.asarray(f)[None])
        label = str(self.pipe[-1].predict(z)[0])
        dist = float(np.linalg.norm(self.Z[self.y == label] - z, axis=1).min())
        novelty = dist / self.radius[label] if np.isfinite(self.radius[label]) else 0.0
        rejected = None
        if label == NOISE:
            rejected = "looks like noise"
        elif novelty > reject_factor:
            rejected = "unfamiliar tap"
        return {"label": label, "conf": round(self._confidence(z), 3), "novelty": round(novelty, 2),
                "rejected": rejected}
