#include "Vfft.h"
#include "Vfft_fft.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <deque>
#include <iostream>
#include <iomanip>
#include <random>

#include <utility>

#include <fftw3.h>

static constexpr double PI = 3.1415926535897932384626433832795028841971693993751058209749445923078164062862089986280348253;

static std::int64_t main_time = 0;

double sc_time_stamp()
{
    return main_time;
}

// real to signed, use convergent rounding
static std::int64_t r2s(const double n)
{
    const std::int64_t nr = static_cast<std::int64_t>(std::round(n*10));
    if (nr % 10 == 5)
    {
        return static_cast<std::int64_t>(nr/10) % 2 == 0 ? static_cast<std::int64_t>(nr/10) : static_cast<std::int64_t>(nr/10) + 1;
    }
    return static_cast<std::int64_t>(std::round(n));
}

// unsigned u of width w to signed (assumes 2s complement representation)
static std::int64_t u2s(std::uint64_t u, const std::int64_t w)
{
    const bool sign = ((u >> (w-1)) & 1) == 1;
    if (sign)
    {
        const std::uint64_t or_mask = ((static_cast<std::uint64_t>(1) << (64-w)) - 1) << w;
        u |= or_mask;
    }
    else
    {
        const std::uint64_t and_mask = (static_cast<std::uint64_t>(1) << (64-w)) - 1;
        u &= and_mask;
    }
    return static_cast<std::int64_t>(u);
}

// ceiling of log2 of an integer
static std::int64_t log2c(std::uint64_t n)
{
    if (n == 0)
    {
        return static_cast<std::int64_t>(-1*std::pow(2,64-1));
    }
    bool is_pow2 = (n & (n - 1)) == 0;
    std::int64_t l2c = 0;
    while ((n >> 1) >= 1)
    {
        n >>= 1;
        l2c++;
    }
    return l2c + (is_pow2 ? 0 : 1);
}

static std::string GetEnv(const std::string &var)
{
    const char* val = std::getenv(var.c_str());
    return val==nullptr ? "" : std::string(val);
}


static void tick(int tickcount, Vfft *tb,
                 VerilatedVcdC *tfp)
{
    main_time = 10 * tickcount;
    tb->eval();
    // log right before clock
    if (tfp != nullptr)
        tfp->dump(tickcount*10-0.0001);
    tb->eval();
    tb->clk = 1;
    tb->eval();
    // log at the posedge
    if (tfp != nullptr)
        tfp->dump(tickcount * 10);
    // log before neg edge
    if (tfp != nullptr)
    {
        tfp->dump(tickcount*10 + 4.999);
        tfp->flush();
    }
    tb->clk  = 0;
    tb->eval();
    // log after negedge
    if (tfp != nullptr)
    {
        tfp->dump(tickcount*10 + 5.0001);
        tfp->flush();
    }
    return;
}

int main(int argc, char**argv)
{
    Verilated::commandArgs(argc,argv);
    Vfft *tb  = new Vfft;
    if (tb == nullptr)
    {
        std::cerr << "Error initializing test" << std::endl;
        return -1;
    }
    VerilatedVcdC *tfp = nullptr;

    const std::int64_t fft_len = tb->fft->get_fft_len();
    const std::int64_t iw      = tb->fft->get_inw();
    const std::int64_t ow      = tb->fft->get_outw();

    const bool dump_traces = (GetEnv("DUMPTRACES") == "1") || (GetEnv("DUMP_TRACES") == "1");
    const std::string tr_f = ((GetEnv("DUMP_F")) != "") ? GetEnv("DUMP_F") : "fft" + std::to_string(fft_len) + "_trace.vcd";

    std::uint64_t seed;
    if (GetEnv("SEED") == "")
    {
        std::random_device dev;
        std::uniform_int_distribution<std::uint64_t> dst_64_bits(0, 18446744073709551615LLU);
        seed = dst_64_bits(dev);
    }
    else
    {
        const std::string hex_chars("0123456789ABCDEF");
        std::string tmp = GetEnv("SEED");
        std::for_each(tmp.begin(), tmp.end(), [](auto &c){ c = toupper(c); });
        if (tmp[0] == '0' &&  tmp[1] == 'X')
        {
            tmp = tmp.substr(2);
        }
        size_t errors = 0;
        std::remove_if(tmp.begin(), tmp.end(),
        [&hex_chars, &errors](const auto c)
        {
            bool to_return = std::find(hex_chars.begin(), hex_chars.end(), c) == hex_chars.end();
            errors += to_return ? 1 : 0;
            return to_return;
        });
        if (errors != 0 || tmp.size() > 16)
        {
            std::cerr << "Error Parsing Seed. Seed must be a 64-bit, unsigned, hexadecimal integer." << std::endl;
            return -1;
        }
        seed = std::stoull(tmp, nullptr, 16);
    }
    std::mt19937 rng(seed);

    if ((fft_len & (fft_len - 1)) != 0)
    {
        std::cerr << "ERROR. FFT LEN " << fft_len << " is not a power of 2" << std::endl;
        delete tb;
        return -1;
    }

    if (dump_traces)
    {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        tb->trace(tfp,99);
        tfp->open(tr_f.c_str());
        std::cerr << "Opening dump file: " << tr_f << std::endl;
        if (tfp == nullptr)
        {
            std::cerr << "Error opening dump file." << std::endl;
            delete tb;
            return -1;
        }
    }

    const std::int64_t mx_ampl = static_cast<std::int64_t>((std::pow(2, iw-1) - 1));
    std::uniform_int_distribution<std::int64_t> dst_in(-mx_ampl, mx_ampl);
    std::uniform_real_distribution<double> dst_T (1, fft_len);

    const std::int64_t stages  = log2c(fft_len);
    const std::int64_t max_err = std::pow(2, ow - iw); // is this right?

    fftw_complex* i_data = static_cast<fftw_complex*>(fftw_malloc(fft_len * sizeof(*i_data)));
    fftw_complex* o_data = static_cast<fftw_complex*>(fftw_malloc(fft_len * sizeof(*o_data)));
    const fftw_plan plan = fftw_plan_dft_1d(fft_len, i_data, o_data, FFTW_FORWARD, FFTW_MEASURE);

    std::cerr << "FFT Test"                                                       << "\n"
              << "Config:"                                                        << "\n"
              << "\tC++ Seed:           " << std::hex << std::uppercase << seed    << "\n" << std::dec
              << "\tFFT_Len:            " << fft_len                               << "\n"
              << "\tFFT_Stages:         " << stages                                << "\n"
              << "\tIn_Bits:            " << iw                                    << "\n"
              << "\tOut_Bits:           " << ow                                    << "\n"
              << "\tOut Bits - In Bits: " << ow - iw                               << "\n"
              << "\tMax Allowed Error:  " << max_err                               << std::endl;

    std::deque<std::pair<double,double>> results;

    std::int64_t sample = 0;
    std::int64_t errors = 0;
    std::int64_t clip_errors = 0;

    int bin_in = 0;
    int fft_in = 0;

    int bin_out = 0;
    int fft_out = 0;

    double max_error = 0;

    int       mode = 0;
    const int num_ffts  = 30;
    const int num_modes = 3;

    double T = 7.0;

    tb->clk    = 0;
    tb->i_init  = 1;
    tb->i_I     = dst_in(rng);
    tb->i_Q     = dst_in(rng);
    tb->i_vld   = 0;
    tb->eval();

    for(std::int64_t i = 1; fft_out < num_ffts; i++)
    {
        tb->i_init  = i <= 1 ? 1 : 0;
        tb->i_vld   = tb->i_init == 1 ? 0 : i%7 != 6 ? 1 : 0;
        if (tb->i_vld == 1)
        {
            // pulse
            if (mode == 0)
            {
                tb->i_I = ((bin_in % fft_len) == (fft_in % fft_len)) ? mx_ampl : 0;
                tb->i_Q = 0;
            }
            // complex sinusoid
            else if (mode == 1)
            {
                tb->i_I     = r2s(mx_ampl*std::cos(sample*2*PI/T));
                tb->i_Q     = r2s(mx_ampl*std::sin(sample*2*PI/T));
            }
            // noise
            else
            {
                tb->i_I     = dst_in(rng);
                tb->i_Q     = dst_in(rng);
            }
        }
        tick (i, tb, tfp);
        if (tb->o_clip_strb != 0)
        {
            std::cerr << "Internal clip detected!" << std::endl;
            clip_errors += 1;
        }
        if(tb->i_init == 1)
        {
            results.clear();
            sample = 0;
            bin_in = 0;
            fft_in = 0;
            bin_out = 0;
            fft_out = 0;
        }
        else if(tb->i_vld == 1)
        {
            i_data[bin_in][0] = u2s(tb->i_I, iw);
            i_data[bin_in][1] = u2s(tb->i_Q, iw);
            sample += 1;
            bin_in = (bin_in + 1) % fft_len;
            if (bin_in == 0)
            {
                mode = (mode + 1) % num_modes;
                T    = dst_T(rng);
                fftw_execute(plan);
                for (int j=0; j < fft_len; j++)
                {
                    results.push_back(std::pair<double,double>(o_data[j][0], o_data[j][1]));
                }
                fft_in += 1;
            }
        }
        if(tb->o_vld == 1 && tb->i_init != 1)
        {
            const fftw_complex tmp = {results.front().first, results.front().second};
            results.pop_front();
            const std::int64_t oI = u2s(tb->o_I, ow);
            const std::int64_t oQ = u2s(tb->o_Q, ow);
            const double      err = std::max(std::abs(tmp[0] - oI), std::abs(tmp[1] - oQ));
            max_error             = std::max(err, max_error);
            if (err > max_err)
            {
                std::cerr << "Error checking outs! fft index: " << std::setw(5) << fft_out << ", FFT_BIN: " << std::setw(5) << bin_out << "\n"
                          << "\tExpected (I,Q): (" << std::fixed << std::setprecision(2) << std::setw(13) << tmp[0]           << "," << std::fixed << std::setprecision(2) << std::setw(13) << tmp[1]      << ")" << "\n"
                          << "\tOut      (I,Q): ("                                       << std::setw(10) << oI     << "   "  << ","                                       << std::setw(10) << oQ << "   " << ")" << std::endl;
                errors++;
            }
            if (bin_out == 0)
            {
                if ((tb->o_new_fft & 1) != 1)
                {
                    std::cerr << "o_new_fft is not as I expect! (low when it should be high)" << std::endl;
                    errors++;
                }
            }
            else
            {
                if((tb->o_new_fft & 1) != 0)
                {
                    std::cerr << "o_new_fft is not as I expect! (high when it should be low)" << std::endl;
                    errors++;
                }
            }
            bin_out = (bin_out + 1) % fft_len;
            fft_out = bin_out == 0 ? fft_out + 1 : fft_out;
        }
    }

    free(i_data);
    free(o_data);
    fftw_destroy_plan(plan);
    if (tfp != nullptr) tfp->close();
    delete tb;
    delete tfp;
    if (errors != 0 || clip_errors != 0)
    {
        std::cerr << errors << " data error" << (errors != 1 ? "s" : "") << "!" << "\n"
                  << "Max error: " << max_error << " (" << std::fixed << std::setprecision(2) << std::log2(max_error) << " bits) out of " << ow << " output bits, " << iw << " input bits\n"
                  << clip_errors << " clip error" << (clip_errors != 1 ? "s" : "") << "!" << std::endl;
        return -1;
    }
    std::cerr << "Max error was: " << max_error << " (" << std::fixed << std::setprecision(2) << std::log2(max_error) << " bits) out of " << ow << " output bits, " << iw << " input bits, which is acceptable\n"
              << "PASS!" << std::endl;
    return 0;
}
