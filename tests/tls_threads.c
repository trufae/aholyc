#include <pthread.h>
#include <stdint.h>

extern int64_t TlsCatch(int64_t ch);

static pthread_mutex_t barrier_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t barrier_cond = PTHREAD_COND_INITIALIZER;
static int barrier_waiting;
static int barrier_generation;

void TlsBarrier(void) {
	pthread_mutex_lock (&barrier_lock);
	int generation = barrier_generation;
	if (++barrier_waiting == 2) {
		barrier_waiting = 0;
		barrier_generation++;
		pthread_cond_broadcast (&barrier_cond);
	} else {
		while (generation == barrier_generation) {
			pthread_cond_wait (&barrier_cond, &barrier_lock);
		}
	}
	pthread_mutex_unlock (&barrier_lock);
}

typedef struct {
	int64_t sent;
	int64_t received;
} ThreadArg;

static void *run_catch(void *opaque) {
	ThreadArg *arg = opaque;
	arg->received = TlsCatch (arg->sent);
	return NULL;
}

int64_t RunTlsThreads(void) {
	pthread_t threads[2];
	ThreadArg args[2] = {{111, 0}, {222, 0}};
	if (pthread_create (&threads[0], NULL, run_catch, &args[0]) ||
	    pthread_create (&threads[1], NULL, run_catch, &args[1])) {
		return 0;
	}
	pthread_join (threads[0], NULL);
	pthread_join (threads[1], NULL);
	return args[0].received == args[0].sent &&
		args[1].received == args[1].sent;
}
