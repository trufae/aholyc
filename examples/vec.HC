// Both forms live in lib/data/vec.HC.  The #exe generator must be included
// at top level: it injects the typed class and its global functions here.

class CPoint
{
  I64 x;
  I64 y;
};

#define VEC_NAME "CPointVec"
#define VEC_TYPE "CPoint"
#include "../lib/data/vec.HC"

I64 CompareI64(U8 *a, U8 *b)
{
  return *a(I64 *) - *b(I64 *);
}

I64 ComparePoint(CPoint *a, CPoint *b)
{
  return a->x - b->x;
}

Bool PointHasY(CPoint *point, U8 *context)
{
  return point->y == *context(I64 *);
}

CVec numbers;
CPointVec points;
CPoint point;
I64 value;
I64 wanted_y;
I64 index;

// Data-driven vector: its element size is supplied at initialization.
VecInit(&numbers, sizeof(I64));
value = 30; VecPush(&numbers, &value);
value = 10; VecPush(&numbers, &value);
value = 20; VecPush(&numbers, &value);
VecSort(&numbers, &CompareI64);
"numbers:";
for (index = 0; index < numbers.count; index++)
  " %d", *VecAt(&numbers, index)(I64 *);
"\nindex of 20: %d\n", VecFind(&numbers, &value, &CompareI64);
VecFini(&numbers);

// Type-specialized vector: direct CPoint storage and statically typed API.
CPointVecInit(&points);
point.x = 30; point.y = 3; CPointVecPush(&points, &point);
point.x = 10; point.y = 1; CPointVecPush(&points, &point);
point.x = 20; point.y = 2; CPointVecPush(&points, &point);
CPointVecSort(&points, &ComparePoint);

wanted_y = 2;
index = CPointVecFindIf(&points, &PointHasY, &wanted_y);
"point with y=2: x=%d\n", CPointVecAt(&points, index)->x;
"points:";
for (index = 0; index < points.count; index++)
  " (%d,%d)", points.data[index].x, points.data[index].y;
"\n";
CPointVecFini(&points);
